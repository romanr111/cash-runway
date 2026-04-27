import SwiftUI
import UniformTypeIdentifiers
#if canImport(LedgerCore)
import LedgerCore
#endif

struct SettingsView: View {
    @Bindable var model: LedgerAppModel
    @State private var isCategoryManagementPresented = false
    @State private var isLabelsPresented = false
    @State private var isTemplatesPresented = false
    @State private var isWalletsPresented = false
    @State private var isLockPresented = false
    @State private var isImporterPresented = false
    @State private var isImportWizardPresented = false
    @State private var isDiagnosticsPresented = false
    @State private var importData = Data()
    @State private var importFileName = ""
    @State private var importPreview = CSVImportPreview(headers: [], sampleRows: [])
    @State private var importMapping = CSVImportMapping(dateColumn: "", amountColumn: nil, debitColumn: nil, creditColumn: nil, merchantColumn: nil, noteColumn: nil, categoryColumn: nil, labelsColumn: nil, walletID: UUID(), defaultKind: .expense)
    @State private var importPreset = CSVPreset.generic

    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 24) {
                    ScreenTitle(title: "More")

                    VStack(alignment: .leading, spacing: 10) {
                        Text("Settings")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(LedgerTheme.textMuted)
                            .textCase(.uppercase)
                            .padding(.horizontal, 4)

                        VStack(spacing: 0) {
                            moreRow(icon: "square.grid.2x2", tint: "#64D1D5", title: "Categories", subtitle: "Manage visibility, order, and merges") {
                                isCategoryManagementPresented = true
                            }
                            rowDivider
                            moreRow(icon: "tag.fill", tint: "#F7A72A", title: "Labels", subtitle: "\(model.labels.count) labels") {
                                isLabelsPresented = true
                            }
                            rowDivider
                            moreRow(icon: "repeat", tint: "#1CC389", title: "Scheduled Transactions", subtitle: "\(model.templates.count) templates") {
                                isTemplatesPresented = true
                            }
                            rowDivider
                            staticRow(icon: "banknote.fill", tint: "#4A80C1", title: "Main Currency", value: "UAH")
                            rowDivider
                            moreRow(icon: "wallet.pass.fill", tint: "#60788A", title: "Manual Wallets", subtitle: "\(model.wallets.count) wallets") {
                                isWalletsPresented = true
                            }
                            rowDivider
                            moreRow(icon: "lock.fill", tint: "#87C56A", title: "App Lock", subtitle: model.lockStore.configuration()?.isEnabled == true ? "Enabled" : "Disabled") {
                                isLockPresented = true
                            }
                        }
                        .background(LedgerTheme.surface, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 28, style: .continuous).stroke(LedgerTheme.line, lineWidth: 1))
                    }

                    VStack(alignment: .leading, spacing: 10) {
                        Text("Data")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(LedgerTheme.textMuted)
                            .textCase(.uppercase)
                            .padding(.horizontal, 4)

                        VStack(spacing: 0) {
                            moreRow(icon: "tray.and.arrow.down.fill", tint: "#5FD4BF", title: "Import CSV", subtitle: "Map and load bank exports") {
                                isImporterPresented = true
                            }
                            rowDivider
                            ShareLink(item: model.exportCSV(), preview: SharePreview("ledger-export.csv")) {
                                rowContent(icon: "square.and.arrow.up.fill", tint: "#E5862F", title: "Export CSV", subtitle: "Share the current filtered export")
                            }
                            .buttonStyle(.plain)
                        }
                        .background(LedgerTheme.surface, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 28, style: .continuous).stroke(LedgerTheme.line, lineWidth: 1))
                    }

                    #if DEBUG
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Debug")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(LedgerTheme.textMuted)
                            .textCase(.uppercase)
                            .padding(.horizontal, 4)

                        VStack(spacing: 0) {
                            moreRow(icon: "wrench.and.screwdriver.fill", tint: "#FF5E57", title: "Diagnostics", subtitle: "Counts and local state") {
                                isDiagnosticsPresented = true
                            }
                        }
                        .background(LedgerTheme.surface, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 28, style: .continuous).stroke(LedgerTheme.line, lineWidth: 1))
                    }
                    #endif
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 16)
                .padding(.bottom, 36)
            }
            .background(LedgerTheme.background)
            .sheet(isPresented: $isCategoryManagementPresented) {
                CategoryManagementView(model: model, initialKind: .expense)
            }
            .sheet(isPresented: $isLabelsPresented) {
                LabelManagementView(model: model)
            }
            .sheet(isPresented: $isTemplatesPresented) {
                ScheduledTransactionsView(model: model)
            }
            .sheet(isPresented: $isWalletsPresented) {
                WalletManagementView(model: model)
            }
            .sheet(isPresented: $isLockPresented) {
                LockConfigurationView(model: model)
            }
            .sheet(isPresented: $isImportWizardPresented) {
                CSVImportWizardView(
                    model: model,
                    preview: importPreview,
                    preset: importPreset,
                    fileName: importFileName,
                    data: importData,
                    mapping: $importMapping
                )
            }
            .sheet(isPresented: $isDiagnosticsPresented) {
                DiagnosticsView(model: model)
            }
            .fileImporter(isPresented: $isImporterPresented, allowedContentTypes: [.commaSeparatedText, .plainText]) { result in
                guard case let .success(url) = result else { return }
                do {
                    let data = try Data(contentsOf: url)
                    let preview = try model.previewCSV(data: data)
                    let preset = model.detectPreset(headers: preview.headers)
                    importData = data
                    importFileName = url.lastPathComponent
                    importPreview = preview
                    importPreset = preset
                    importMapping = defaultMapping(headers: preview.headers, preset: preset)
                    isImportWizardPresented = true
                } catch {
                    model.errorMessage = error.localizedDescription
                }
            }
        }
    }

    private var rowDivider: some View {
        Divider().overlay(LedgerTheme.line).padding(.leading, 72)
    }

    private func moreRow(icon: String, tint: String, title: String, subtitle: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            rowContent(icon: icon, tint: tint, title: title, subtitle: subtitle)
        }
        .buttonStyle(.plain)
    }

    private func staticRow(icon: String, tint: String, title: String, value: String) -> some View {
        HStack(spacing: 14) {
            CategoryGlyph(iconName: icon, colorHex: tint, size: 44)
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(LedgerTheme.textPrimary)
                Text(value)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(LedgerTheme.textSecondary)
            }
            Spacer()
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 16)
    }

    private func rowContent(icon: String, tint: String, title: String, subtitle: String) -> some View {
        HStack(spacing: 14) {
            CategoryGlyph(iconName: icon, colorHex: tint, size: 44)
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(LedgerTheme.textPrimary)
                Text(subtitle)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(LedgerTheme.textSecondary)
            }
            Spacer()
            Image(systemName: "chevron.right")
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(LedgerTheme.textMuted)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 16)
    }

    private func defaultMapping(headers: [String], preset: CSVPreset) -> CSVImportMapping {
        let walletID = model.wallets.first?.id ?? UUID()
        let dateColumn = header(named: ["Дата операції", "Date", "date"], in: headers) ?? headers.first ?? ""
        let amountColumn = header(named: ["Сума в грн", "Amount", "amount", "sum"], in: headers)
        let debitColumn = header(named: ["Debit", "debit", "Витрати"], in: headers)
        let creditColumn = header(named: ["Credit", "credit", "Надходження"], in: headers)
        let typeColumn = header(named: ["Type", "type"], in: headers)
        let walletColumn = header(named: ["Wallet", "wallet"], in: headers)
        let currencyColumn = header(named: ["Currency", "currency"], in: headers)
        let merchantColumn = header(named: ["Description", "description", "Merchant", "merchant", "Призначення"], in: headers)
        let noteColumn = header(named: ["Comment", "comment", "Note", "note"], in: headers)
        let categoryColumn = header(named: ["Category", "category", "Category name", "category name"], in: headers)
        let labelsColumn = header(named: ["Labels", "labels", "Tags"], in: headers)
        let authorColumn = header(named: ["Author", "author"], in: headers)

        return CSVImportMapping(
            dateColumn: dateColumn,
            amountColumn: amountColumn,
            debitColumn: preset == .generic ? debitColumn : nil,
            creditColumn: preset == .generic ? creditColumn : nil,
            merchantColumn: merchantColumn,
            noteColumn: noteColumn,
            categoryColumn: categoryColumn,
            labelsColumn: labelsColumn,
            walletID: walletID,
            defaultKind: .expense,
            typeColumn: typeColumn,
            walletColumn: walletColumn,
            currencyColumn: currencyColumn,
            authorColumn: authorColumn
        )
    }

    private func header(named candidates: [String], in headers: [String]) -> String? {
        headers.first { header in
            candidates.contains { $0.caseInsensitiveCompare(header) == .orderedSame }
        }
    }
}

private struct LabelManagementView: View {
    @Environment(\.dismiss) private var dismiss
    @Bindable var model: LedgerAppModel
    @State private var isEditorPresented = false
    @State private var labelDraft = LedgerLabel(id: UUID(), name: "", colorHex: "#60788A", createdAt: .now, updatedAt: .now)

    var body: some View {
        NavigationStack {
            List {
                ForEach(model.labels) { label in
                    Button(label.name) {
                        labelDraft = label
                        isEditorPresented = true
                    }
                }
            }
            .navigationTitle("Labels")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Done") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        labelDraft = LedgerLabel(id: UUID(), name: "", colorHex: "#60788A", createdAt: .now, updatedAt: .now)
                        isEditorPresented = true
                    } label: {
                        Image(systemName: "plus")
                    }
                }
            }
            .sheet(isPresented: $isEditorPresented) {
                LabelEditorView(model: model, label: $labelDraft)
            }
        }
    }
}

private struct WalletManagementView: View {
    @Environment(\.dismiss) private var dismiss
    @Bindable var model: LedgerAppModel
    @State private var isEditorPresented = false
    @State private var walletDraft = Wallet(id: UUID(), name: "", kind: .cash, colorHex: "#60788A", iconName: "wallet.pass.fill", startingBalanceMinor: 0, currentBalanceMinor: 0, isArchived: false, sortOrder: 0, createdAt: .now, updatedAt: .now)

    var body: some View {
        NavigationStack {
            List {
                ForEach(model.wallets) { wallet in
                    Button(wallet.name) {
                        walletDraft = wallet
                        isEditorPresented = true
                    }
                }
            }
            .navigationTitle("Manual Wallets")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Done") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        walletDraft = Wallet(id: UUID(), name: "", kind: .cash, colorHex: "#60788A", iconName: "wallet.pass.fill", startingBalanceMinor: 0, currentBalanceMinor: 0, isArchived: false, sortOrder: model.wallets.count, createdAt: .now, updatedAt: .now)
                        isEditorPresented = true
                    } label: {
                        Image(systemName: "plus")
                    }
                }
            }
            .sheet(isPresented: $isEditorPresented) {
                WalletEditorView(model: model, wallet: $walletDraft)
            }
        }
    }
}

private struct ScheduledTransactionsView: View {
    @Environment(\.dismiss) private var dismiss
    @Bindable var model: LedgerAppModel
    @State private var templateDraft = RecurringTemplate(id: UUID(), kind: .expense, walletID: UUID(), counterpartyWalletID: nil, amountMinor: 0, categoryID: nil, merchant: nil, note: nil, ruleType: .monthly, ruleInterval: 1, dayOfMonth: 1, weekday: nil, startDate: .now, endDate: nil, isActive: true, createdAt: .now, updatedAt: .now)
    @State private var isEditorPresented = false

    var body: some View {
        NavigationStack {
            List {
                Section("Templates") {
                    ForEach(model.templates) { template in
                        Button(template.merchant ?? template.kind.rawValue.capitalized) {
                            templateDraft = template
                            isEditorPresented = true
                        }
                    }
                }
                Section("Upcoming") {
                    ForEach(model.instances) { instance in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(instance.dueDate.formatted(date: .abbreviated, time: .omitted))
                            Text(instance.status.rawValue.capitalized)
                                .foregroundStyle(LedgerTheme.textSecondary)
                        }
                    }
                }
            }
            .navigationTitle("Scheduled Transactions")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Done") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        templateDraft = RecurringTemplate(
                            id: UUID(),
                            kind: .expense,
                            walletID: model.wallets.first?.id ?? UUID(),
                            counterpartyWalletID: model.wallets.dropFirst().first?.id,
                            amountMinor: 0,
                            categoryID: model.expenseCategories.first?.id,
                            merchant: nil,
                            note: nil,
                            ruleType: .monthly,
                            ruleInterval: 1,
                            dayOfMonth: 1,
                            weekday: nil,
                            startDate: .now,
                            endDate: nil,
                            isActive: true,
                            createdAt: .now,
                            updatedAt: .now
                        )
                        isEditorPresented = true
                    } label: {
                        Image(systemName: "plus")
                    }
                }
            }
            .sheet(isPresented: $isEditorPresented) {
                RecurringTemplateEditorView(model: model, template: $templateDraft)
            }
        }
    }
}

private struct LockConfigurationView: View {
    @Environment(\.dismiss) private var dismiss
    @Bindable var model: LedgerAppModel
    @State private var pin = ""
    @State private var biometrics = true

    var body: some View {
        NavigationStack {
            Form {
                SecureField("PIN", text: $pin)
                    .keyboardType(.numberPad)
                Toggle("Enable biometrics", isOn: $biometrics)
            }
            .navigationTitle("App Lock")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Save") {
                        model.enableLock(pin: pin, biometrics: biometrics)
                        dismiss()
                    }
                    .disabled(pin.isEmpty)
                }
            }
        }
    }
}

private struct DiagnosticsView: View {
    @Environment(\.dismiss) private var dismiss
    @Bindable var model: LedgerAppModel

    var body: some View {
        NavigationStack {
            List {
                Text("Wallets: \(model.wallets.count)")
                Text("Transactions: \(model.transactions.count)")
                Text("Budgets: \(model.budgets.count)")
                Text("Templates: \(model.templates.count)")
                Text("Labels: \(model.labels.count)")
            }
            .navigationTitle("Diagnostics")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}

private struct CSVImportWizardView: View {
    @Environment(\.dismiss) private var dismiss
    @Bindable var model: LedgerAppModel
    let preview: CSVImportPreview
    let preset: CSVPreset
    let fileName: String
    let data: Data
    @Binding var mapping: CSVImportMapping

    var body: some View {
        NavigationStack {
            Form {
                Section("Source") {
                    Text(fileName)
                    Text("Preset: \(preset.rawValue)")
                        .foregroundStyle(LedgerTheme.textSecondary)
                }

                Section("Mapping") {
                    Picker("Wallet", selection: $mapping.walletID) {
                        ForEach(model.wallets) { wallet in
                            Text(wallet.name).tag(wallet.id)
                        }
                    }
                    Picker("Kind", selection: $mapping.defaultKind) {
                        Text("Expense").tag(TransactionDraft.Kind.expense)
                        Text("Income").tag(TransactionDraft.Kind.income)
                    }
                    requiredPicker("Date", selection: $mapping.dateColumn)
                    optionalPicker("Amount", selection: Binding(
                        get: { mapping.amountColumn },
                        set: {
                            mapping.amountColumn = $0
                            if $0 != nil {
                                mapping.debitColumn = nil
                                mapping.creditColumn = nil
                            }
                        }
                    ))
                    optionalPicker("Debit", selection: Binding(
                        get: { mapping.debitColumn },
                        set: {
                            mapping.debitColumn = $0
                            if $0 != nil { mapping.amountColumn = nil }
                        }
                    ))
                    optionalPicker("Credit", selection: Binding(
                        get: { mapping.creditColumn },
                        set: {
                            mapping.creditColumn = $0
                            if $0 != nil { mapping.amountColumn = nil }
                        }
                    ))
                    optionalPicker("Type", selection: $mapping.typeColumn)
                    optionalPicker("Wallet", selection: $mapping.walletColumn)
                    optionalPicker("Currency", selection: $mapping.currencyColumn)
                    optionalPicker("Merchant", selection: $mapping.merchantColumn)
                    optionalPicker("Note", selection: $mapping.noteColumn)
                    optionalPicker("Category", selection: $mapping.categoryColumn)
                    optionalPicker("Labels", selection: $mapping.labelsColumn)
                }

                Section("Preview") {
                    ForEach(Array(preview.sampleRows.enumerated()), id: \.offset) { _, row in
                        VStack(alignment: .leading, spacing: 4) {
                            ForEach(Array(zip(preview.headers, row)), id: \.0) { header, value in
                                HStack {
                                    Text(header)
                                        .foregroundStyle(LedgerTheme.textSecondary)
                                    Spacer()
                                    Text(value)
                                        .multilineTextAlignment(.trailing)
                                }
                            }
                        }
                        .padding(.vertical, 6)
                    }
                }
            }
            .navigationTitle("Import CSV")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Import") {
                        model.importCSV(data: data, fileName: fileName, mapping: mapping)
                        dismiss()
                    }
                    .disabled(mapping.dateColumn.isEmpty || (mapping.amountColumn == nil && mapping.debitColumn == nil && mapping.creditColumn == nil))
                }
            }
        }
    }

    private func requiredPicker(_ title: String, selection: Binding<String>) -> some View {
        Picker(title, selection: selection) {
            ForEach(preview.headers, id: \.self) { header in
                Text(header).tag(header)
            }
        }
    }

    private func optionalPicker(_ title: String, selection: Binding<String?>) -> some View {
        Picker(title, selection: selection) {
            Text("None").tag(String?.none)
            ForEach(preview.headers, id: \.self) { header in
                Text(header).tag(String?.some(header))
            }
        }
    }
}
