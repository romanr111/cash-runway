import Foundation
import SwiftUI
import CashRunwayCore
import OSLog

private let logger = Logger(subsystem: "dev.roman.cashrunway", category: "editors")

struct TransactionEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @Bindable var model: CashRunwayAppModel
    @Binding var draft: TransactionDraft
    @State private var composerState = TransactionComposerState(
        selectedKind: .expense,
        selectedCategoryID: nil,
        amountText: "",
        quickDateLabel: "Yesterday?",
        selectedLabelIDs: []
    )
    @State private var composerModal: ComposerModal?
    @State private var createRecurringTemplate = false
    @State private var recurringRuleType = RecurrenceRuleType.monthly
    @State private var recurringInterval = 1
    @State private var recurringDayOfMonth = 1
    @State private var recurringWeekday = 1
    @State private var focusAmountAfterCategorySheet = false
    @State private var openCategoryManagementAfterCategorySheet = false
    @State private var showsLabelsPanel = false
    @State private var showsRecurringPanel = false
    @FocusState private var focusedField: ComposerField?

    @State private var amountError: String?
    @State private var originalCategoryID: UUID?
    @State private var isCategoryLearningPromptPresented = false
    @State private var showsDeleteConfirmation = false
    @State private var pendingLearnTransactionID: UUID?
    @State private var pendingLearnCategoryID: UUID?

    private enum ComposerField: Hashable {
        case amount
        case note
    }

    private enum ComposerModal: String, Identifiable {
        case categoryManagement
        case category

        var id: String { rawValue }
    }

    var body: some View {
        NavigationStack {
            ZStack(alignment: .top) {
                CashRunwayTheme.background.ignoresSafeArea()

                VStack(spacing: 0) {
                    composerHeader
                    detailsPane
                }

            }
            .toolbar(.hidden, for: .navigationBar)
            .sheet(item: $composerModal) { modal in
                switch modal {
                case .category:
                    TransactionCategorySheet(
                        model: model,
                        draft: $draft,
                        composerState: $composerState,
                        onCategorySelected: {
                            focusAmountAfterCategorySheet = true
                        },
                        onOpenManagement: {
                            openCategoryManagementAfterCategorySheet = true
                        }
                    )
                    .presentationDetents([.fraction(0.54), .large])
                    .presentationDragIndicator(.visible)
                    .accessibilityIdentifier(CashRunwayAccessibilityID.transactionCategorySheet)
                case .categoryManagement:
                    CategoryManagementView(model: model, initialKind: draft.kind == .income ? .income : .expense)
                }
            }
            .sheet(isPresented: $showsLabelsPanel) {
                labelsSheet
                    .presentationDetents([.fraction(0.55), .large])
                    .presentationDragIndicator(.visible)
            }
            .sheet(isPresented: $showsRecurringPanel) {
                recurringSheet
                    .presentationDetents([.fraction(0.45), .large])
                    .presentationDragIndicator(.visible)
            }
            .alert("Use this category next time?", isPresented: $isCategoryLearningPromptPresented) {
                Button("Apply next time") {
                    commitTransaction(learnCategoryRule: true)
                }
                Button("Only this transaction", role: .cancel) {
                    commitTransaction(learnCategoryRule: false)
                }
            } message: {
                Text(categoryLearningPromptMessage)
            }
            .alert("Delete Transaction?", isPresented: $showsDeleteConfirmation) {
                Button("Cancel", role: .cancel) {}
                Button("Delete", role: .destructive) {
                    deleteCurrentTransaction()
                }
            } message: {
                Text("This transaction will be permanently removed.")
            }
            .onChange(of: composerModal) { _, modal in
                guard modal == nil else { return }
                let shouldOpenManagement = openCategoryManagementAfterCategorySheet
                let shouldFocusAmount = focusAmountAfterCategorySheet
                openCategoryManagementAfterCategorySheet = false
                focusAmountAfterCategorySheet = false
                DispatchQueue.main.async {
                    if shouldOpenManagement {
                        composerModal = .categoryManagement
                    } else if shouldFocusAmount {
                        focusedField = .amount
                    }
                }
            }
            .onAppear {
                originalCategoryID = draft.categoryID
                composerState = TransactionComposerState(
                    selectedKind: draft.kind,
                    selectedCategoryID: draft.categoryID,
                    amountText: draft.amountMinor == 0 ? "" : MoneyFormatter.plainString(from: draft.amountMinor),
                    quickDateLabel: "Yesterday?",
                    selectedLabelIDs: draft.labelIDs
                )
                recurringDayOfMonth = Calendar.current.component(.day, from: draft.occurredAt)
                recurringWeekday = Calendar.current.component(.weekday, from: draft.occurredAt)
                if draft.categoryID == nil {
                    draft.categoryID = availableCategories.first?.id
                    composerState.selectedCategoryID = draft.categoryID
                }
                if draft.walletID == UUID(), let firstWallet = model.wallets.first {
                    draft.walletID = firstWallet.id
                    draft.currencyCode = firstWallet.currencyCode
                }
                if !model.wallets.isEmpty, !model.wallets.contains(where: { $0.id == draft.walletID }), let firstWallet = model.wallets.first {
                    draft.walletID = firstWallet.id
                    draft.currencyCode = firstWallet.currencyCode
                }
                if draft.id == nil {
                    composerModal = .category
                }
            }
        }
    }

    private var composerHeader: some View {
        VStack(spacing: 20) {
            HStack {
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundStyle(CashRunwayTheme.textPrimary)
                        .frame(width: 40, height: 40)
                        .background(.white.opacity(0.72), in: Circle())
                }
                .accessibilityIdentifier(CashRunwayAccessibilityID.transactionCloseButton)

                Spacer()

                Text(draft.id == nil ? "Add a Transaction" : "Edit Transaction")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(CashRunwayTheme.textPrimary)

                Spacer()

                Button {
                    composerModal = .category
                } label: {
                    Image(systemName: "square.grid.2x2")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(CashRunwayTheme.textPrimary)
                        .frame(width: 40, height: 40)
                        .background(.white.opacity(0.72), in: Circle())
                }
            }

            HStack(alignment: .center, spacing: 18) {
                Button {
                    composerModal = .category
                } label: {
                    ZStack {
                        Circle()
                            .stroke(style: StrokeStyle(lineWidth: 2, dash: [5, 5]))
                            .foregroundStyle(.white.opacity(0.8))
                            .frame(width: 92, height: 92)
                        if let selectedCategory = selectedCategory {
                            CategoryGlyph(iconName: selectedCategory.iconName, colorHex: selectedCategory.colorHex, size: 82)
                        } else {
                            Image(systemName: "plus")
                                .font(.system(size: 28, weight: .bold))
                                .foregroundStyle(.white)
                        }
                    }
                }
                .accessibilityIdentifier(CashRunwayAccessibilityID.transactionCategoryButton)

                Spacer()

                VStack(alignment: .trailing, spacing: 10) {
                    HStack(spacing: 10) {
                        TextField("0.00", text: $composerState.amountText)
                            .keyboardType(.decimalPad)
                            .focused($focusedField, equals: .amount)
                            .multilineTextAlignment(.trailing)
                            .font(.system(size: 42, weight: .bold, design: .rounded))
                            .foregroundStyle(CashRunwayTheme.textPrimary)
                            .frame(minWidth: 140)
                            .toolbar {
                                ToolbarItemGroup(placement: .keyboard) {
                                    Spacer()
                                    Button("Done") {
                                        focusedField = nil
                                    }
                                    .font(.system(size: 17, weight: .semibold))
                                    .foregroundStyle(CashRunwayTheme.accent)
                                }
                            }
                            .accessibilityIdentifier(CashRunwayAccessibilityID.transactionAmountField)
                        Text(draft.currencyCode.rawValue)
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(CashRunwayTheme.textPrimary)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(.white.opacity(0.72), in: Capsule())
                    }

                    Text(selectedCategory?.name ?? categoryPrompt)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(CashRunwayTheme.textSecondary)
                }
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 16)
        .padding(.bottom, 28)
        .background(CashRunwayTheme.composerHeader)
        .clipShape(RoundedRectangle(cornerRadius: 34, style: .continuous))
    }

    private var detailsPane: some View {
        ZStack(alignment: .top) {
            ScrollViewReader { _ in
                ScrollView(showsIndicators: false) {
                    VStack(spacing: 0) {
                        walletSelectionRow

                        divider

                        VStack(spacing: 12) {
                            HStack {
                                Text("Date")
                                    .font(.system(size: 17, weight: .semibold))
                                    .foregroundStyle(CashRunwayTheme.textPrimary)
                                Spacer()
                                DatePicker("", selection: $draft.occurredAt, displayedComponents: [.date])
                                    .labelsHidden()
                                    .datePickerStyle(.compact)
                                    .tint(CashRunwayTheme.accentDark)
                            }

                            HStack(spacing: 4) {
                                Spacer()
                                HStack(spacing: 4) {
                                    dateShortcutButton("Today", isSelected: Calendar.current.isDateInToday(draft.occurredAt)) {
                                        draft.occurredAt = .now
                                    }
                                    dateShortcutButton("Yesterday", isSelected: Calendar.current.isDateInYesterday(draft.occurredAt)) {
                                        if let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: .now) {
                                            draft.occurredAt = yesterday
                                        }
                                    }
                                }
                                .padding(4)
                                .background(CashRunwayTheme.pill, in: Capsule())
                            }
                        }
                        .padding(.vertical, 18)

                        divider

                        VStack(spacing: 0) {
                            textFieldRow(
                                title: "Note",
                                text: $draft.note,
                                placeholder: "Add a note",
                                identifier: CashRunwayAccessibilityID.transactionNoteField,
                                focus: $focusedField,
                                focusValue: .note
                            )
                            divider
                            Button {
                                focusedField = nil
                                showsLabelsPanel = true
                                showsRecurringPanel = false
                            } label: {
                                HStack {
                                    Text("Labels")
                                        .font(.system(size: 17, weight: .semibold))
                                        .foregroundStyle(CashRunwayTheme.textPrimary)
                                    Spacer()
                                    Text(labelSummary)
                                        .font(.system(size: 16))
                                        .foregroundStyle(CashRunwayTheme.textSecondary)
                                        .accessibilityIdentifier(CashRunwayAccessibilityID.transactionLabelsSummary)
                                    Image(systemName: "chevron.right")
                                        .font(.system(size: 14, weight: .bold))
                                        .foregroundStyle(CashRunwayTheme.textMuted)
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.vertical, 18)
                                .contentShape(Rectangle())
                            }
                            .accessibilityIdentifier(CashRunwayAccessibilityID.transactionLabelsButton)
                            .buttonStyle(.plain)

                            if draft.kind == .transfer {
                                divider
                                HStack {
                                    Text("Transfer To")
                                        .font(.system(size: 17, weight: .semibold))
                                        .foregroundStyle(CashRunwayTheme.textPrimary)
                                    Spacer()
                            Menu {
                                ForEach(model.wallets.filter { $0.id != draft.walletID && $0.currencyCode == draft.currencyCode }) { wallet in
                                    Button(wallet.name) { draft.destinationWalletID = wallet.id }
                                }
                            } label: {

                                        HStack(spacing: 8) {
                                            Text(transferDestinationName)
                                                .font(.system(size: 16))
                                                .foregroundStyle(CashRunwayTheme.textSecondary)
                                            Image(systemName: "chevron.right")
                                                .font(.system(size: 14, weight: .bold))
                                                .foregroundStyle(CashRunwayTheme.textMuted)
                                        }
                                    }
                                    .accessibilityIdentifier(CashRunwayAccessibilityID.transactionTransferDestinationMenu)
                                }
                                .padding(.vertical, 18)
                            }

                            divider

                            Button {
                                focusedField = nil
                                showsRecurringPanel = true
                                showsLabelsPanel = false
                            } label: {
                                HStack {
                                    Text("Repeat")
                                        .font(.system(size: 17, weight: .semibold))
                                        .foregroundStyle(CashRunwayTheme.textPrimary)
                                    Spacer()
                                    Text(createRecurringTemplate ? recurringSummary : "One-time")
                                        .font(.system(size: 16))
                                        .foregroundStyle(CashRunwayTheme.textSecondary)
                                        .accessibilityIdentifier(CashRunwayAccessibilityID.transactionRepeatSummary)
                                    Image(systemName: "chevron.right")
                                        .font(.system(size: 14, weight: .bold))
                                        .foregroundStyle(CashRunwayTheme.textMuted)
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.vertical, 18)
                                .contentShape(Rectangle())
                            }
                            .accessibilityIdentifier(CashRunwayAccessibilityID.transactionRepeatButton)
                            .buttonStyle(.plain)
                        }
                        .padding(.horizontal, 20)
                        .background(CashRunwayTheme.surface, in: RoundedRectangle(cornerRadius: 30, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 30, style: .continuous).stroke(CashRunwayTheme.line, lineWidth: 1))
                        .padding(.top, 20)

                        Button {
                            amountError = nil
                            guard let parsed = try? MoneyFormatter.parseMinorUnits(composerState.amountText), parsed > 0 else {
                                amountError = "Enter a valid amount greater than zero."
                                return
                            }
                            draft.kind = composerState.selectedKind
                            draft.categoryID = composerState.selectedCategoryID
                            draft.labelIDs = composerState.selectedLabelIDs
                            draft.amountMinor = parsed
                            if shouldOfferCategoryLearning,
                               let transactionID = draft.id,
                               let categoryID = draft.categoryID {
                                pendingLearnTransactionID = transactionID
                                pendingLearnCategoryID = categoryID
                                isCategoryLearningPromptPresented = true
                            } else {
                                commitTransaction(learnCategoryRule: false)
                            }
                        } label: {
                            Text("Save Transaction")
                                .font(.system(size: 18, weight: .bold))
                                .foregroundStyle(.white)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 18)
                                .background(CashRunwayTheme.accentDark, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
                        }
                        .padding(.top, 20)
                        .accessibilityIdentifier(CashRunwayAccessibilityID.transactionSaveButton)

                        if draft.id != nil {
                            Button(role: .destructive) {
                                showsDeleteConfirmation = true
                            } label: {
                                HStack {
                                    Image(systemName: "trash")
                                    Text("Delete Transaction")
                                }
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundStyle(CashRunwayTheme.negative)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 16)
                                .background(CashRunwayTheme.negative.opacity(0.08), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
                                .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).stroke(CashRunwayTheme.negative.opacity(0.18), lineWidth: 1))
                            }
                            .buttonStyle(.plain)
                            .padding(.top, 12)
                            .accessibilityIdentifier(CashRunwayAccessibilityID.transactionDetailsDeleteButton)
                        }

                        if let amountError {
                            Text(amountError)
                                .font(.system(size: 14, weight: .medium))
                                .foregroundStyle(CashRunwayTheme.negative)
                                .frame(maxWidth: .infinity, alignment: .center)
                                .padding(.top, 8)
                                .accessibilityIdentifier(CashRunwayAccessibilityID.transactionValidationAmount)
                        }

                        Spacer().frame(height: 32)
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 18)
                }
            }
        }
    }

    private var walletSelectionRow: some View {
        let canSelect = model.wallets.count > 1
        return Menu {
            ForEach(model.wallets) { wallet in
                Button {
                    selectWallet(wallet)
                } label: {
                    HStack {
                        Text(wallet.name)
                            .font(.system(size: 17))
                            .foregroundStyle(CashRunwayTheme.textPrimary)
                        Spacer()
                        if wallet.id == draft.walletID {
                            Image(systemName: "checkmark")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(CashRunwayTheme.accentDark)
                        }
                    }
                }
            }
        } label: {
            HStack {
                Text(L10n.string("Wallet"))
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(CashRunwayTheme.textPrimary)
                Spacer()
                Text(walletName(for: draft.walletID))
                    .font(.system(size: 16))
                    .foregroundStyle(CashRunwayTheme.textSecondary)
                if canSelect {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(CashRunwayTheme.textMuted)
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 18)
            .background(CashRunwayTheme.surface, in: RoundedRectangle(cornerRadius: 30, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 30, style: .continuous).stroke(CashRunwayTheme.line, lineWidth: 1))
        }
        .disabled(!canSelect)
        .opacity(canSelect ? 1.0 : 0.6)
        .buttonStyle(.plain)
        .accessibilityIdentifier(CashRunwayAccessibilityID.transactionWalletMenu)
    }

    private var recurringSheet: some View {
        NavigationStack {
            VStack(spacing: 0) {
                HStack {
                    Text("Recurring")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(CashRunwayTheme.textPrimary)
                    Spacer()
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 18)

                Divider().overlay(CashRunwayTheme.line)

                VStack(alignment: .leading, spacing: 14) {
                    Toggle("Save as recurring template", isOn: $createRecurringTemplate)
                    if createRecurringTemplate {
                        Picker("Rule", selection: $recurringRuleType) {
                            ForEach(RecurrenceRuleType.allCases, id: \.self) { rule in
                                Text(rule.rawValue.capitalized).tag(rule)
                            }
                        }
                        Stepper("Interval \(recurringInterval)", value: $recurringInterval, in: 1...12)
                        if recurringRuleType == .monthly || recurringRuleType == .yearly {
                            Stepper("Day \(recurringDayOfMonth)", value: $recurringDayOfMonth, in: 1...28)
                        }
                        if recurringRuleType == .weekly {
                            Picker("Weekday", selection: $recurringWeekday) {
                                ForEach(1...7, id: \.self) { weekday in
                                    Text(weekdayName(weekday)).tag(weekday)
                                }
                            }
                        }
                    }
                }
            }
            .padding(.vertical, 18)
            .padding(.horizontal, 20)
            .background(CashRunwayTheme.surface, in: RoundedRectangle(cornerRadius: 30, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 30, style: .continuous).stroke(CashRunwayTheme.line, lineWidth: 1))
            .frame(maxWidth: .infinity, minHeight: 220, maxHeight: 320, alignment: .top)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") {
                        showsRecurringPanel = false
                    }
                    .accessibilityIdentifier(CashRunwayAccessibilityID.transactionRecurringSheetDoneButton)
                }
            }
            .navigationBarTitleDisplayMode(.inline)
        }
        .accessibilityIdentifier(CashRunwayAccessibilityID.transactionRecurringSheet)
        .accessibilityElement(children: .contain)
    }

    private var labelsSheet: some View {
        let labels: [CashRunwayLabel] = {
            guard ProcessInfo.processInfo.environment["CASH_RUNWAY_UI_TEST_MODE"] == "1" else {
                return model.labels
            }

            let uiTestLabels = model.labels.filter { $0.name.hasPrefix("UITEST-") }
            return uiTestLabels.isEmpty ? model.labels : uiTestLabels
        }()

        return NavigationStack {
            VStack(spacing: 0) {
                HStack {
                    Text("Labels")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(CashRunwayTheme.textPrimary)
                    Spacer()
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 18)

                Divider().overlay(CashRunwayTheme.line)

                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(labels) { label in
                            Button {
                                if composerState.selectedLabelIDs.contains(label.id) {
                                    composerState.selectedLabelIDs.removeAll { $0 == label.id }
                                } else {
                                    composerState.selectedLabelIDs.append(label.id)
                                }
                                composerState.selectedLabelIDs = Array(Set(composerState.selectedLabelIDs)).sorted { $0.uuidString < $1.uuidString }
                                draft.labelIDs = composerState.selectedLabelIDs
                            } label: {
                                HStack {
                                    Text(label.name)
                                        .font(.system(size: 17, weight: .semibold))
                                        .foregroundStyle(CashRunwayTheme.textPrimary)
                                    Spacer()
                                    Image(systemName: composerState.selectedLabelIDs.contains(label.id) ? "checkmark.circle.fill" : "circle")
                                        .foregroundStyle(CashRunwayTheme.textMuted)
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.horizontal, 20)
                                .padding(.vertical, 14)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .accessibilityIdentifier(label.name)
                            .accessibilityValue(composerState.selectedLabelIDs.contains(label.id) ? "selected" : "not selected")

                            if label.id != labels.last?.id {
                                Divider().overlay(CashRunwayTheme.line)
                            }
                        }
                    }
                }
            }
            .padding(.bottom, 8)
            .padding(.horizontal, 20)
            .background(CashRunwayTheme.surface, in: RoundedRectangle(cornerRadius: 30, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 30, style: .continuous).stroke(CashRunwayTheme.line, lineWidth: 1))
            .frame(maxWidth: .infinity, minHeight: 260, maxHeight: 360, alignment: .top)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") {
                        showsLabelsPanel = false
                    }
                    .accessibilityIdentifier(CashRunwayAccessibilityID.transactionLabelsSheetDoneButton)
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .onAppear {
                logger.debug("labels sheet appeared")
            }
        }
        .accessibilityIdentifier(CashRunwayAccessibilityID.transactionLabelsSheet)
        .accessibilityElement(children: .contain)
    }

    private var recurringTemplate: RecurringTemplate? {
        guard createRecurringTemplate else { return nil }
        let kind: RecurringTemplateKind = switch composerState.selectedKind {
        case .expense: .expense
        case .income: .income
        case .transfer: .transfer
        }
        return RecurringTemplate(
            id: UUID(),
            kind: kind,
            walletID: draft.walletID,
            counterpartyWalletID: draft.destinationWalletID,
            amountMinor: draft.amountMinor,
            currencyCode: draft.currencyCode,
            categoryID: composerState.selectedCategoryID,
            merchant: draft.merchant.isEmpty ? nil : draft.merchant,
            note: draft.note.isEmpty ? nil : draft.note,
            ruleType: recurringRuleType,
            ruleInterval: recurringInterval,
            dayOfMonth: recurringRuleType == .monthly || recurringRuleType == .yearly ? recurringDayOfMonth : nil,
            weekday: recurringRuleType == .weekly ? recurringWeekday : nil,
            startDate: draft.occurredAt,
            endDate: nil,
            isActive: true,
            createdAt: .now,
            updatedAt: .now
        )
    }

    private func weekdayName(_ weekday: Int) -> String {
        Calendar.current.weekdaySymbols[max(0, min(weekday - 1, Calendar.current.weekdaySymbols.count - 1))]
    }

    private var availableCategories: [CashRunwayCategory] {
        switch composerState.selectedKind {
        case .expense:
            model.expenseCategories
        case .income:
            model.incomeCategories
        case .transfer:
            []
        }
    }

    private var selectedCategory: CashRunwayCategory? {
        availableCategories.first(where: { $0.id == composerState.selectedCategoryID })
    }

    private var categoryPrompt: String {
        switch composerState.selectedKind {
        case .expense:
            "Expense category"
        case .income:
            "Income category"
        case .transfer:
            "Transfer"
        }
    }

    private var labelSummary: String {
        let names = model.labels.filter { composerState.selectedLabelIDs.contains($0.id) }.map(\.name)
        return names.isEmpty ? "None" : names.joined(separator: ", ")
    }

    private var recurringSummary: String {
        recurringRuleType.rawValue.capitalized + " every \(recurringInterval)"
    }

    private var transferDestinationName: String {
        if let destinationID = draft.destinationWalletID,
           let wallet = model.wallets.first(where: { $0.id == destinationID }) {
            return wallet.name
        }
        return "Select wallet"
    }

    private var shouldOfferCategoryLearning: Bool {
        draft.source == .bankSync
            && draft.id != nil
            && draft.kind == .expense
            && draft.categoryID != nil
            && originalCategoryID != draft.categoryID
    }

    private var categoryLearningPromptMessage: String {
        let merchant = draft.merchant.isEmpty ? "this merchant" : draft.merchant
        let oldName = categoryName(originalCategoryID) ?? L10n.string("category.otherExpense")
        let newName = categoryName(pendingLearnCategoryID ?? draft.categoryID) ?? L10n.string("this category")
        return L10n.string("You changed \"%@\" from %@ to %@. Apply %@ to future %@ transactions?", merchant, oldName, newName, newName, merchant)
    }

    private func categoryName(_ id: UUID?) -> String? {
        guard let id else { return nil }
        if let category = model.expenseCategories.first(where: { $0.id == id })
            ?? model.incomeCategories.first(where: { $0.id == id }) {
            return BuiltInCategoryDisplayName.name(category)
        }
        return nil
    }

    private func commitTransaction(learnCategoryRule: Bool) {
        model.saveTransaction(draft, recurringTemplate: recurringTemplate)
        if learnCategoryRule,
           let transactionID = pendingLearnTransactionID ?? draft.id,
           let categoryID = pendingLearnCategoryID ?? draft.categoryID {
            model.bankSyncViewModel.learnBankCategoryRule(transactionID: transactionID, categoryID: categoryID)
        }
        dismiss()
    }

    private func deleteCurrentTransaction() {
        guard let transactionID = draft.id else { return }
        model.deleteTransaction(id: transactionID)
        dismiss()
    }

    private var divider: some View {
        Divider().overlay(CashRunwayTheme.line)
    }

    private func walletName(for id: UUID) -> String {
        model.wallets.first(where: { $0.id == id })?.name ?? L10n.string("Select wallet")
    }

    private func selectWallet(_ wallet: Wallet) {
        draft.walletID = wallet.id
        draft.currencyCode = wallet.currencyCode
        if draft.kind == .transfer {
            if draft.destinationWalletID == wallet.id {
                draft.destinationWalletID = nil
            } else if let destinationID = draft.destinationWalletID,
                      let destination = model.wallets.first(where: { $0.id == destinationID }),
                      destination.currencyCode != wallet.currencyCode {
                draft.destinationWalletID = nil
            }
        }
    }

    private func rowButton(title: String, value: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack {
                Text(title)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(CashRunwayTheme.textPrimary)
                Spacer()
                Text(value)
                    .font(.system(size: 16))
                    .foregroundStyle(CashRunwayTheme.textSecondary)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 18)
            .background(CashRunwayTheme.surface, in: RoundedRectangle(cornerRadius: 30, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 30, style: .continuous).stroke(CashRunwayTheme.line, lineWidth: 1))
        }
        .buttonStyle(.plain)
    }

    private func textFieldRow(
        title: String,
        text: Binding<String>,
        placeholder: String,
        identifier: String? = nil,
        focus: FocusState<ComposerField?>.Binding? = nil,
        focusValue: ComposerField? = nil
    ) -> some View {
        HStack {
            Text(title)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(CashRunwayTheme.textPrimary)
            Spacer()
            if let focus, let focusValue {
                TextField(placeholder, text: text)
                    .focused(focus, equals: focusValue)
                    .multilineTextAlignment(.trailing)
                    .foregroundStyle(CashRunwayTheme.textSecondary)
                    .accessibilityIdentifier(identifier ?? "")
            } else {
                TextField(placeholder, text: text)
                    .multilineTextAlignment(.trailing)
                    .foregroundStyle(CashRunwayTheme.textSecondary)
                    .accessibilityIdentifier(identifier ?? "")
            }
        }
        .padding(.vertical, 18)
    }

    private func dateShortcutButton(_ title: String, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(isSelected ? CashRunwayTheme.accentDark : CashRunwayTheme.textSecondary)
                .frame(width: 96)
                .padding(.vertical, 8)
                .background(isSelected ? CashRunwayTheme.accentMuted : Color.clear, in: Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityValue(isSelected ? "selected" : "not selected")
        .accessibilityIdentifier(title == "Today" ? CashRunwayAccessibilityID.transactionDateTodayButton : CashRunwayAccessibilityID.transactionDateYesterdayButton)
    }
}

private struct TransactionCategorySheet: View {
    @Environment(\.dismiss) private var dismiss
    @Bindable var model: CashRunwayAppModel
    @Binding var draft: TransactionDraft
    @Binding var composerState: TransactionComposerState
    let onCategorySelected: () -> Void
    let onOpenManagement: () -> Void

    var body: some View {
        NavigationStack {
            VStack(spacing: 18) {
                Picker("Type", selection: $composerState.selectedKind) {
                    Text("Expenses").tag(TransactionDraft.Kind.expense)
                    Text("Income").tag(TransactionDraft.Kind.income)
                    Text("Transfer").tag(TransactionDraft.Kind.transfer)
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, 20)
                .accessibilityIdentifier(CashRunwayAccessibilityID.transactionKindPicker)
                .onChange(of: composerState.selectedKind) { _, kind in
                    draft.kind = kind
                    switch kind {
                    case .expense:
                        composerState.selectedCategoryID = model.expenseCategories.first?.id
                        draft.destinationWalletID = nil
                    case .income:
                        composerState.selectedCategoryID = model.incomeCategories.first?.id
                        draft.destinationWalletID = nil
                    case .transfer:
                        composerState.selectedCategoryID = nil
                        draft.destinationWalletID = model.wallets.first(where: { $0.id != draft.walletID && $0.currencyCode == draft.currencyCode })?.id
                    }
                }

                if composerState.selectedKind == .transfer {
                    VStack(spacing: 14) {
                        Image(systemName: "arrow.left.arrow.right.circle.fill")
                            .font(.system(size: 42))
                            .foregroundStyle(CashRunwayTheme.accent)
                        Text("Transfers do not use categories.")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(CashRunwayTheme.textPrimary)
                        Text("Choose the destination wallet in the form below.")
                            .font(.system(size: 14))
                            .foregroundStyle(CashRunwayTheme.textSecondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    ScrollView {
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 92), spacing: 18)], spacing: 18) {
                            ForEach(availableCategories) { category in
                                Button {
                                    draft.kind = composerState.selectedKind
                                    composerState.selectedCategoryID = category.id
                                    draft.categoryID = category.id
                                    onCategorySelected()
                                    dismiss()
                                } label: {
                                    VStack(spacing: 10) {
                                        ZStack {
                                            Circle()
                                                .stroke(composerState.selectedCategoryID == category.id ? CashRunwayTheme.textPrimary : .clear, lineWidth: 2)
                                                .frame(width: 76, height: 76)
                                            CategoryGlyph(iconName: category.iconName, colorHex: category.colorHex, size: 62)
                                        }
                                        .frame(width: 80, height: 80)
                                        Text(BuiltInCategoryDisplayName.name(category))
                                            .font(.system(size: 13, weight: .semibold))
                                            .foregroundStyle(CashRunwayTheme.textPrimary)
                                            .multilineTextAlignment(.center)
                                    }
                                }
                                .buttonStyle(.plain)
                                .accessibilityIdentifier(CashRunwayAccessibilityID.transactionCategory(category.name))
                            }
                        }
                        .padding(.horizontal, 20)
                        .padding(.bottom, 24)
                    }
                }
            }
            .background(CashRunwayTheme.background)
            .navigationTitle("Transaction Category")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        onOpenManagement()
                        dismiss()
                    } label: {
                        Image(systemName: "gearshape")
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        draft.kind = composerState.selectedKind
                        draft.categoryID = composerState.selectedCategoryID
                        dismiss()
                    } label: {
                        Image(systemName: "checkmark")
                            .font(.system(size: 15, weight: .bold))
                    }
                    .accessibilityIdentifier(CashRunwayAccessibilityID.transactionCategorySheetDoneButton)
                }
            }
        }
    }

    private var availableCategories: [CashRunwayCategory] {
        composerState.selectedKind == .income ? model.incomeCategories : model.expenseCategories
    }
}
