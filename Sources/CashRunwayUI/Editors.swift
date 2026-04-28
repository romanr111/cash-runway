import SwiftUI
#if canImport(CashRunwayCore)
import CashRunwayCore
#endif

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
    @State private var showsCategorySheet = true
    @State private var showsLabelsSheet = false
    @State private var showsRecurringSheet = false
    @State private var showsCategoryManagement = false
    @State private var createRecurringTemplate = false
    @State private var recurringRuleType = RecurrenceRuleType.monthly
    @State private var recurringInterval = 1
    @State private var recurringDayOfMonth = 1
    @State private var recurringWeekday = 1
    @State private var focusAmountAfterCategorySheet = false
    @State private var openCategoryManagementAfterCategorySheet = false
    @FocusState private var amountFieldFocused: Bool

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
            .sheet(isPresented: $showsCategorySheet) {
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
            }
            .sheet(isPresented: $showsLabelsSheet) {
                NavigationStack {
                    List {
                        ForEach(model.labels) { label in
                            Toggle(label.name, isOn: Binding(
                                get: { composerState.selectedLabelIDs.contains(label.id) },
                                set: { isSelected in
                                    if isSelected {
                                        composerState.selectedLabelIDs.append(label.id)
                                    } else {
                                        composerState.selectedLabelIDs.removeAll { $0 == label.id }
                                    }
                                    composerState.selectedLabelIDs = Array(Set(composerState.selectedLabelIDs)).sorted { $0.uuidString < $1.uuidString }
                                    draft.labelIDs = composerState.selectedLabelIDs
                                }
                            ))
                        }
                    }
                    .navigationTitle("Labels")
                    .toolbar {
                        ToolbarItem(placement: .topBarTrailing) {
                            Button("Done") { showsLabelsSheet = false }
                        }
                    }
                }
            }
            .sheet(isPresented: $showsRecurringSheet) {
                recurringSheet
                    .presentationDetents([.medium])
                    .presentationDragIndicator(.visible)
            }
            .sheet(isPresented: $showsCategoryManagement) {
                CategoryManagementView(model: model, initialKind: draft.kind == .income ? .income : .expense)
            }
            .onChange(of: showsCategorySheet) { _, isPresented in
                guard !isPresented else { return }
                let shouldOpenManagement = openCategoryManagementAfterCategorySheet
                let shouldFocusAmount = focusAmountAfterCategorySheet
                openCategoryManagementAfterCategorySheet = false
                focusAmountAfterCategorySheet = false
                DispatchQueue.main.async {
                    if shouldOpenManagement {
                        showsCategoryManagement = true
                    } else if shouldFocusAmount {
                        amountFieldFocused = true
                    }
                }
            }
            .onAppear {
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
                if draft.walletID == UUID(), let firstWalletID = model.wallets.first?.id {
                    draft.walletID = firstWalletID
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

                Spacer()

                Text("Add a Transaction")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(CashRunwayTheme.textPrimary)

                Spacer()

                Button {
                    showsCategorySheet = true
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
                    showsCategorySheet = true
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

                Spacer()

                VStack(alignment: .trailing, spacing: 10) {
                    HStack(spacing: 10) {
                        TextField("0.00", text: $composerState.amountText)
                            .keyboardType(.decimalPad)
                            .focused($amountFieldFocused)
                            .multilineTextAlignment(.trailing)
                            .font(.system(size: 42, weight: .bold, design: .rounded))
                            .foregroundStyle(CashRunwayTheme.textPrimary)
                            .frame(minWidth: 140)
                        Text("UAH")
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
        ScrollView(showsIndicators: false) {
            VStack(spacing: 0) {
                rowButton(title: "Wallet", value: walletName(for: draft.walletID), action: {})
                    .overlay(alignment: .trailing) {
                        Menu {
                            ForEach(model.wallets) { wallet in
                                Button(wallet.name) { draft.walletID = wallet.id }
                            }
                        } label: {
                            Image(systemName: "chevron.right")
                                .font(.system(size: 14, weight: .bold))
                                .foregroundStyle(CashRunwayTheme.textMuted)
                        }
                        .padding(.trailing, 2)
                    }

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
                    textFieldRow(title: "Note", text: $draft.note, placeholder: "Add a note")
                    divider
                    Button {
                        showsLabelsSheet = true
                    } label: {
                        HStack {
                            Text("Labels")
                                .font(.system(size: 17, weight: .semibold))
                                .foregroundStyle(CashRunwayTheme.textPrimary)
                            Spacer()
                            Text(labelSummary)
                                .font(.system(size: 16))
                                .foregroundStyle(CashRunwayTheme.textSecondary)
                            Image(systemName: "chevron.right")
                                .font(.system(size: 14, weight: .bold))
                                .foregroundStyle(CashRunwayTheme.textMuted)
                        }
                        .padding(.vertical, 18)
                    }

                    if draft.kind == .transfer {
                        divider
                        HStack {
                            Text("Transfer To")
                                .font(.system(size: 17, weight: .semibold))
                                .foregroundStyle(CashRunwayTheme.textPrimary)
                            Spacer()
                            Menu {
                                ForEach(model.wallets.filter { $0.id != draft.walletID }) { wallet in
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
                        }
                        .padding(.vertical, 18)
                    }

                    divider

                    Button {
                        showsRecurringSheet = true
                    } label: {
                        HStack {
                            Text("Repeat")
                                .font(.system(size: 17, weight: .semibold))
                                .foregroundStyle(CashRunwayTheme.textPrimary)
                            Spacer()
                            Text(createRecurringTemplate ? recurringSummary : "One-time")
                                .font(.system(size: 16))
                                .foregroundStyle(CashRunwayTheme.textSecondary)
                            Image(systemName: "chevron.right")
                                .font(.system(size: 14, weight: .bold))
                                .foregroundStyle(CashRunwayTheme.textMuted)
                        }
                        .padding(.vertical, 18)
                    }
                }
                .padding(.horizontal, 20)
                .background(CashRunwayTheme.surface, in: RoundedRectangle(cornerRadius: 30, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 30, style: .continuous).stroke(CashRunwayTheme.line, lineWidth: 1))
                .padding(.top, 20)

                Button {
                    draft.kind = composerState.selectedKind
                    draft.categoryID = composerState.selectedCategoryID
                    draft.labelIDs = composerState.selectedLabelIDs
                    draft.amountMinor = (try? MoneyFormatter.parseMinorUnits(composerState.amountText)) ?? 0
                    model.saveTransaction(draft, recurringTemplate: recurringTemplate)
                    dismiss()
                } label: {
                    Text("Save Transaction")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 18)
                        .background(CashRunwayTheme.accentDark, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
                }
                .padding(.top, 20)
                .padding(.bottom, 32)
            }
            .padding(.horizontal, 20)
            .padding(.top, 18)
        }
    }

    private var recurringSheet: some View {
        NavigationStack {
            Form {
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
            .navigationTitle("Recurring")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { showsRecurringSheet = false }
                }
            }
        }
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

    private var divider: some View {
        Divider().overlay(CashRunwayTheme.line)
    }

    private func walletName(for id: UUID) -> String {
        model.wallets.first(where: { $0.id == id })?.name ?? "Select wallet"
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

    private func textFieldRow(title: String, text: Binding<String>, placeholder: String) -> some View {
        HStack {
            Text(title)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(CashRunwayTheme.textPrimary)
            Spacer()
            TextField(placeholder, text: text)
                .multilineTextAlignment(.trailing)
                .foregroundStyle(CashRunwayTheme.textSecondary)
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
                        draft.destinationWalletID = model.wallets.first(where: { $0.id != draft.walletID })?.id
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
                                        Text(category.name)
                                            .font(.system(size: 13, weight: .semibold))
                                            .foregroundStyle(CashRunwayTheme.textPrimary)
                                            .multilineTextAlignment(.center)
                                    }
                                }
                                .buttonStyle(.plain)
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
                }
            }
        }
    }

    private var availableCategories: [CashRunwayCategory] {
        composerState.selectedKind == .income ? model.incomeCategories : model.expenseCategories
    }
}

struct CategoryManagementView: View {
    @Environment(\.dismiss) private var dismiss
    @Bindable var model: CashRunwayAppModel
    @State private var selectedKind: CategoryKind
    @State private var items: [CategoryManagementItem] = []
    @State private var showsEditor = false
    @State private var showsMergeSheet = false
    @State private var categoryDraft = CashRunwayCategory(id: UUID(), name: "", kind: .expense, iconName: "questionmark.app.fill", colorHex: "#7E57C2", parentID: nil, isSystem: false, isArchived: false, sortOrder: 0, createdAt: .now, updatedAt: .now)

    init(model: CashRunwayAppModel, initialKind: CategoryKind) {
        self.model = model
        _selectedKind = State(initialValue: initialKind)
    }

    var body: some View {
        NavigationStack {
            List {
                Picker("Kind", selection: $selectedKind) {
                    Text("Expenses").tag(CategoryKind.expense)
                    Text("Income").tag(CategoryKind.income)
                }
                .pickerStyle(.segmented)
                .listRowBackground(CashRunwayTheme.background)
                .listRowSeparator(.hidden)

                ForEach(items) { item in
                    HStack(spacing: 14) {
                        CategoryGlyph(iconName: item.category.iconName, colorHex: item.category.colorHex, size: 48)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(item.category.name)
                                .font(.system(size: 17, weight: .semibold))
                                .foregroundStyle(CashRunwayTheme.textPrimary)
                            Text("\(item.transactionCount) transactions in \(item.walletCount) wallets")
                                .font(.system(size: 14, weight: .medium))
                                .foregroundStyle(CashRunwayTheme.textSecondary)
                        }
                        Spacer()
                        Button {
                            model.toggleCategoryVisibility(item.category)
                            reload()
                        } label: {
                            Image(systemName: item.isVisible ? "eye.fill" : "eye.slash.fill")
                                .font(.system(size: 17, weight: .semibold))
                                .foregroundStyle(item.isVisible ? CashRunwayTheme.accentDark : CashRunwayTheme.textMuted)
                                .frame(width: 36, height: 36)
                        }
                        Image(systemName: "line.3.horizontal")
                            .font(.system(size: 17, weight: .medium))
                            .foregroundStyle(CashRunwayTheme.textMuted)
                    }
                    .padding(.vertical, 8)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        categoryDraft = item.category
                        showsEditor = true
                    }
                }
                .onMove(perform: moveItems)
            }
            .environment(\.editMode, .constant(.active))
            .scrollContentBackground(.hidden)
            .background(CashRunwayTheme.background)
            .navigationTitle("Categories")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Back") { dismiss() }
                }
            }
            .safeAreaInset(edge: .bottom) {
                HStack {
                    Button {
                        categoryDraft = CashRunwayCategory(
                            id: UUID(),
                            name: "",
                            kind: selectedKind,
                            iconName: "questionmark.app.fill",
                            colorHex: "#7E57C2",
                            parentID: nil,
                            isSystem: false,
                            isArchived: false,
                            sortOrder: items.count,
                            createdAt: .now,
                            updatedAt: .now
                        )
                        showsEditor = true
                    } label: {
                        Image(systemName: "plus")
                            .font(.system(size: 18, weight: .bold))
                            .foregroundStyle(.white)
                            .frame(width: 52, height: 52)
                            .background(CashRunwayTheme.accent, in: Circle())
                    }

                    Spacer()

                    Button("Merge categories...") {
                        showsMergeSheet = true
                    }
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(CashRunwayTheme.textPrimary)
                    .padding(.horizontal, 18)
                    .padding(.vertical, 14)
                    .background(CashRunwayTheme.surface, in: Capsule())
                    .overlay(Capsule().stroke(CashRunwayTheme.line, lineWidth: 1))
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 12)
                .background(.ultraThinMaterial)
            }
            .sheet(isPresented: $showsEditor, onDismiss: reload) {
                CategoryEditorView(model: model, category: $categoryDraft)
            }
            .sheet(isPresented: $showsMergeSheet, onDismiss: reload) {
                CategoryMergeView(model: model, kind: selectedKind)
            }
            .onAppear(perform: reload)
            .onChange(of: selectedKind) { _, _ in reload() }
        }
    }

    private func reload() {
        items = model.categoryManagementItems(kind: selectedKind)
    }

    private func moveItems(from source: IndexSet, to destination: Int) {
        items.move(fromOffsets: source, toOffset: destination)
        model.reorderCategories(kind: selectedKind, orderedCategoryIDs: items.map(\.category.id))
        reload()
    }
}

private struct CategoryMergeView: View {
    @Environment(\.dismiss) private var dismiss
    @Bindable var model: CashRunwayAppModel
    let kind: CategoryKind
    @State private var sourceID: UUID?
    @State private var destinationID: UUID?

    var body: some View {
        NavigationStack {
            Form {
                Picker("From", selection: $sourceID) {
                    Text("Select category").tag(UUID?.none)
                    ForEach(categories) { category in
                        Text(category.name).tag(UUID?.some(category.id))
                    }
                }
                Picker("Into", selection: $destinationID) {
                    Text("Select category").tag(UUID?.none)
                    ForEach(categories.filter { $0.id != sourceID }) { category in
                        Text(category.name).tag(UUID?.some(category.id))
                    }
                }
            }
            .navigationTitle("Merge Categories")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Merge") {
                        if let sourceID, let destinationID {
                            model.mergeCategory(oldCategoryID: sourceID, into: destinationID)
                            dismiss()
                        }
                    }
                    .disabled(sourceID == nil || destinationID == nil)
                }
            }
        }
    }

    private var categories: [CashRunwayCategory] {
        kind == .income ? model.incomeCategories : model.expenseCategories
    }
}

struct BudgetEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @Bindable var model: CashRunwayAppModel
    @Binding var budget: Budget
    @State private var limitText = ""

    var body: some View {
        NavigationStack {
            Form {
                Picker("Category", selection: $budget.categoryID) {
                    ForEach(model.expenseCategories) { category in
                        Text(category.name).tag(category.id)
                    }
                }
                TextField("Limit", text: $limitText)
                    .keyboardType(.decimalPad)
                Toggle("Archive budget", isOn: $budget.isArchived)
            }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Save") {
                        budget.limitMinor = (try? MoneyFormatter.parseMinorUnits(limitText)) ?? 0
                        budget.updatedAt = .now
                        model.saveBudget(budget)
                        dismiss()
                    }
                }
            }
        }
        .onAppear {
            limitText = budget.limitMinor == 0 ? "" : MoneyFormatter.plainString(from: budget.limitMinor)
        }
    }
}

struct WalletEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @Bindable var model: CashRunwayAppModel
    @Binding var wallet: Wallet
    @State private var balanceText = ""

    var body: some View {
        NavigationStack {
            Form {
                TextField("Name", text: $wallet.name)
                Picker("Kind", selection: $wallet.kind) {
                    ForEach(WalletKind.allCases, id: \.self) { kind in
                        Text(kind.rawValue.capitalized).tag(kind)
                    }
                }
                TextField("Starting Balance", text: $balanceText)
                    .keyboardType(.decimalPad)
            }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Save") {
                        let balance = (try? MoneyFormatter.parseMinorUnits(balanceText)) ?? 0
                        wallet.startingBalanceMinor = balance
                        wallet.currentBalanceMinor = balance
                        wallet.updatedAt = .now
                        model.saveWallet(wallet)
                        dismiss()
                    }
                }
            }
        }
        .onAppear {
            balanceText = wallet.startingBalanceMinor == 0 ? "" : MoneyFormatter.plainString(from: wallet.startingBalanceMinor)
        }
    }
}

struct CategoryEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @Bindable var model: CashRunwayAppModel
    @Binding var category: CashRunwayCategory

    var body: some View {
        NavigationStack {
            Form {
                TextField("Name", text: $category.name)
                Picker("Kind", selection: $category.kind) {
                    Text("Expense").tag(CategoryKind.expense)
                    Text("Income").tag(CategoryKind.income)
                }
                TextField("Color Hex", text: Binding(get: { category.colorHex ?? "" }, set: { category.colorHex = $0 }))
                TextField("Symbol", text: Binding(get: { category.iconName ?? "" }, set: { category.iconName = $0 }))
            }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Save") {
                        category.updatedAt = .now
                        model.saveCategory(category)
                        dismiss()
                    }
                }
            }
        }
    }
}

struct LabelEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @Bindable var model: CashRunwayAppModel
    @Binding var label: CashRunwayLabel

    var body: some View {
        NavigationStack {
            Form {
                TextField("Name", text: $label.name)
                TextField("Color Hex", text: Binding(get: { label.colorHex ?? "" }, set: { label.colorHex = $0 }))
            }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Save") {
                        label.updatedAt = .now
                        model.saveLabel(label)
                        dismiss()
                    }
                }
            }
        }
    }
}

struct RecurringTemplateEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @Bindable var model: CashRunwayAppModel
    @Binding var template: RecurringTemplate
    @State private var amountText = ""
    @State private var usesEndDate = false

    var body: some View {
        NavigationStack {
            Form {
                Picker("Kind", selection: $template.kind) {
                    Text("Expense").tag(RecurringTemplateKind.expense)
                    Text("Income").tag(RecurringTemplateKind.income)
                    Text("Transfer").tag(RecurringTemplateKind.transfer)
                }
                Picker("Wallet", selection: $template.walletID) {
                    ForEach(model.wallets) { wallet in
                        Text(wallet.name).tag(wallet.id)
                    }
                }
                if template.kind == .transfer {
                    Picker("Counterparty", selection: Binding(get: { template.counterpartyWalletID ?? model.wallets.dropFirst().first?.id ?? template.walletID }, set: { template.counterpartyWalletID = $0 })) {
                        ForEach(model.wallets.filter { $0.id != template.walletID }) { wallet in
                            Text(wallet.name).tag(wallet.id)
                        }
                    }
                } else {
                    Picker("Category", selection: Binding(get: { template.categoryID ?? model.expenseCategories.first?.id ?? UUID() }, set: { template.categoryID = $0 })) {
                        ForEach(template.kind == .income ? model.incomeCategories : model.expenseCategories) { category in
                            Text(category.name).tag(category.id)
                        }
                    }
                }
                TextField("Amount", text: $amountText)
                TextField("Merchant", text: Binding(get: { template.merchant ?? "" }, set: { template.merchant = $0.isEmpty ? nil : $0 }))
                TextField("Note", text: Binding(get: { template.note ?? "" }, set: { template.note = $0.isEmpty ? nil : $0 }))
                Picker("Rule", selection: $template.ruleType) {
                    ForEach(RecurrenceRuleType.allCases, id: \.self) { rule in
                        Text(rule.rawValue.capitalized).tag(rule)
                    }
                }
                Stepper("Interval \(template.ruleInterval)", value: $template.ruleInterval, in: 1...12)
                if template.ruleType == .monthly || template.ruleType == .yearly {
                    Stepper("Day \(template.dayOfMonth ?? 1)", value: Binding(
                        get: { template.dayOfMonth ?? 1 },
                        set: { template.dayOfMonth = $0 }
                    ), in: 1...28)
                }
                if template.ruleType == .weekly {
                    Picker("Weekday", selection: Binding(
                        get: { template.weekday ?? 1 },
                        set: { template.weekday = $0 }
                    )) {
                        ForEach(1...7, id: \.self) { weekday in
                            Text(Calendar.current.weekdaySymbols[weekday - 1]).tag(weekday)
                        }
                    }
                }
                DatePicker("Start", selection: $template.startDate, displayedComponents: [.date])
                Toggle("End date", isOn: $usesEndDate)
                if usesEndDate {
                    DatePicker("End", selection: Binding(
                        get: { template.endDate ?? template.startDate },
                        set: { template.endDate = $0 }
                    ), displayedComponents: [.date])
                }
            }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Save") {
                        template.amountMinor = (try? MoneyFormatter.parseMinorUnits(amountText)) ?? 0
                        template.updatedAt = .now
                        model.saveTemplate(template)
                        dismiss()
                    }
                }
            }
        }
        .onAppear {
            amountText = template.amountMinor == 0 ? "" : MoneyFormatter.plainString(from: template.amountMinor)
            usesEndDate = template.endDate != nil
        }
    }
}

struct RecurringInstanceEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @Bindable var model: CashRunwayAppModel
    @Binding var instance: RecurringInstance
    let categories: [CashRunwayCategory]
    @State private var amountText = ""

    var body: some View {
        NavigationStack {
            Form {
                DatePicker("Due Date", selection: $instance.dueDate, displayedComponents: [.date])
                Picker("Status", selection: $instance.status) {
                    ForEach(RecurringInstanceStatus.allCases, id: \.self) { status in
                        Text(status.rawValue.capitalized).tag(status)
                    }
                }
                TextField("Override Amount", text: $amountText)
                    .keyboardType(.decimalPad)
                Picker("Override Category", selection: Binding(
                    get: { instance.overrideCategoryID },
                    set: { instance.overrideCategoryID = $0 }
                )) {
                    Text("Keep Template Category").tag(UUID?.none)
                    ForEach(categories) { category in
                        Text(category.name).tag(UUID?.some(category.id))
                    }
                }
                TextField("Override Merchant", text: Binding(
                    get: { instance.overrideMerchant ?? "" },
                    set: { instance.overrideMerchant = $0.isEmpty ? nil : $0 }
                ))
                TextField("Override Note", text: Binding(
                    get: { instance.overrideNote ?? "" },
                    set: { instance.overrideNote = $0.isEmpty ? nil : $0 }
                ))
            }
            .navigationTitle("Occurrence")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Save") {
                        instance.overrideAmountMinor = amountText.isEmpty ? nil : (try? MoneyFormatter.parseMinorUnits(amountText))
                        instance.dayKey = DateKeys.dayKey(for: instance.dueDate)
                        instance.updatedAt = .now
                        if instance.status == .scheduled, instance.dueDate != Calendar.current.startOfDay(for: instance.dueDate) {
                            instance.status = .postponed
                        }
                        model.saveInstance(instance)
                        dismiss()
                    }
                }
            }
            .onAppear {
                amountText = instance.overrideAmountMinor.map(MoneyFormatter.plainString(from:)) ?? ""
            }
        }
    }
}
