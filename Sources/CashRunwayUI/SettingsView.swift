import Foundation
import SwiftUI
import UniformTypeIdentifiers
#if canImport(UIKit)
import UIKit
#endif
#if canImport(CashRunwayCore)
import CashRunwayCore
#endif

struct SettingsView: View {
    @Bindable var model: CashRunwayAppModel
    @State private var isCategoryManagementPresented = false
    @State private var isLabelsPresented = false
    @State private var isTemplatesPresented = false
    @State private var isWalletsPresented = false
    @State private var isLockPresented = false
    @State private var isImporterPresented = false
    @State private var isImportReviewPresented = false
    @State private var isDiagnosticsPresented = false
    @State private var importData = Data()
    @State private var importFileName = ""
    @State private var importPreview = CSVImportPreview(headers: [], sampleRows: [], totalRows: 0)
    @State private var importMapping = CSVImportMapping(dateColumn: "", amountColumn: nil, debitColumn: nil, creditColumn: nil, merchantColumn: nil, noteColumn: nil, categoryColumn: nil, labelsColumn: nil, walletID: UUID(), defaultKind: .expense)
    @State private var importPreset = CSVPreset.generic
    @State private var isImportPreparing = false
    @State private var importPreparationProgress = 0.0
    @State private var importPreparationStatus = ""
    @State private var importPreparationError: String?

    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 24) {
                    ScreenTitle(title: "More")

                    VStack(alignment: .leading, spacing: 10) {
                        Text("Settings")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(CashRunwayTheme.textMuted)
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
                        .background(CashRunwayTheme.surface, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 28, style: .continuous).stroke(CashRunwayTheme.line, lineWidth: 1))
                    }

                    VStack(alignment: .leading, spacing: 10) {
                        Text("Data")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(CashRunwayTheme.textMuted)
                            .textCase(.uppercase)
                            .padding(.horizontal, 4)

                        VStack(spacing: 0) {
                            moreRow(icon: "tray.and.arrow.down.fill", tint: "#5FD4BF", title: "Import CSV", subtitle: "Map and load bank exports") {
                                isImporterPresented = true
                            }
                            rowDivider
                            ShareLink(item: model.exportCSV(), preview: SharePreview("cash-runway-export.csv")) {
                                rowContent(icon: "square.and.arrow.up.fill", tint: "#E5862F", title: "Export CSV", subtitle: "Share the current filtered export")
                            }
                            .buttonStyle(.plain)
                        }
                        .background(CashRunwayTheme.surface, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 28, style: .continuous).stroke(CashRunwayTheme.line, lineWidth: 1))
                    }

                    #if DEBUG
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Debug")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(CashRunwayTheme.textMuted)
                            .textCase(.uppercase)
                            .padding(.horizontal, 4)

                        VStack(spacing: 0) {
                            moreRow(icon: "wrench.and.screwdriver.fill", tint: "#FF5E57", title: "Diagnostics", subtitle: "Counts and local state") {
                                isDiagnosticsPresented = true
                            }
                        }
                        .background(CashRunwayTheme.surface, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 28, style: .continuous).stroke(CashRunwayTheme.line, lineWidth: 1))
                    }
                    #endif
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 16)
                .padding(.bottom, 36)
            }
            .background(CashRunwayTheme.background)
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
            .sheet(isPresented: $isImportReviewPresented) {
                CSVImportReviewView(
                    model: model,
                    preview: importPreview,
                    preset: importPreset,
                    fileName: importFileName,
                    data: importData,
                    mapping: $importMapping,
                    isPreparing: isImportPreparing,
                    preparationProgress: importPreparationProgress,
                    preparationStatus: importPreparationStatus,
                    preparationError: importPreparationError
                )
            }
            .sheet(isPresented: $isDiagnosticsPresented) {
                DiagnosticsView(model: model)
            }
            .sheet(isPresented: $isImporterPresented) {
                #if canImport(UIKit)
                CSVDocumentPicker(allowedContentTypes: [.commaSeparatedText, .plainText]) { result in
                    handleImporterResult(result)
                }
                #else
                Text("CSV import is unavailable on this platform.")
                #endif
            }
        }
    }

    private func handleImporterResult(_ result: Result<URL, any Error>) {
        isImporterPresented = false
        switch result {
        case let .success(url):
            prepareImport(from: url)
        case let .failure(error):
            if let pickerError = error as? CSVDocumentPickerError, pickerError == .cancelled {
                return
            }
            model.errorMessage = error.localizedDescription
        }
    }

    private func prepareImport(from url: URL) {
        let fileName = url.lastPathComponent.isEmpty ? "import.csv" : url.lastPathComponent
        let csvService = model.csvService

        importData = Data()
        importFileName = fileName
        importPreview = CSVImportPreview(headers: [], sampleRows: [], totalRows: 0)
        importPreset = .generic
        importMapping = defaultMapping(headers: [], preset: .generic)
        importPreparationError = nil
        importPreparationProgress = 0.12
        importPreparationStatus = "Opening selected file..."
        isImportPreparing = true
        isImportReviewPresented = true

        Task {
            do {
                let data = try await Task.detached(priority: .userInitiated) {
                    try CSVImportFileReader.readData(from: url)
                }.value

                await MainActor.run {
                    importPreparationProgress = 0.55
                    importPreparationStatus = "Reading CSV rows..."
                }

                let preparedImport = try await Task.detached(priority: .userInitiated) {
                    let preview = try csvService.preview(data: data)
                    let preset = csvService.detectPreset(headers: preview.headers)
                    return CSVPreparedImport(data: data, preview: preview, preset: preset)
                }.value

                await MainActor.run {
                    importData = preparedImport.data
                    importPreview = preparedImport.preview
                    importPreset = preparedImport.preset
                    importMapping = defaultMapping(headers: preparedImport.preview.headers, preset: preparedImport.preset)
                    importPreparationProgress = 1.0
                    importPreparationStatus = "Ready to review."
                    isImportPreparing = false
                }
            } catch {
                await MainActor.run {
                    importPreparationError = error.localizedDescription
                    importPreparationProgress = 0.0
                    importPreparationStatus = ""
                    isImportPreparing = false
                }
            }
        }
    }

    private var rowDivider: some View {
        Divider().overlay(CashRunwayTheme.line).padding(.leading, 72)
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
                    .foregroundStyle(CashRunwayTheme.textPrimary)
                Text(value)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(CashRunwayTheme.textSecondary)
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
                    .foregroundStyle(CashRunwayTheme.textPrimary)
                Text(subtitle)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(CashRunwayTheme.textSecondary)
            }
            Spacer()
            Image(systemName: "chevron.right")
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(CashRunwayTheme.textMuted)
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

private enum CSVDocumentPickerError: LocalizedError, Equatable {
    case emptySelection
    case cancelled

    var errorDescription: String? {
        switch self {
        case .emptySelection:
            "No CSV file was selected."
        case .cancelled:
            nil
        }
    }
}

#if canImport(UIKit)
private struct CSVDocumentPicker: UIViewControllerRepresentable {
    let allowedContentTypes: [UTType]
    let onCompletion: (Result<URL, any Error>) -> Void

    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        let controller = UIDocumentPickerViewController(forOpeningContentTypes: allowedContentTypes, asCopy: true)
        controller.allowsMultipleSelection = false
        controller.delegate = context.coordinator
        return controller
    }

    func updateUIViewController(_ uiViewController: UIDocumentPickerViewController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(onCompletion: onCompletion)
    }

    final class Coordinator: NSObject, UIDocumentPickerDelegate {
        let onCompletion: (Result<URL, any Error>) -> Void

        init(onCompletion: @escaping (Result<URL, any Error>) -> Void) {
            self.onCompletion = onCompletion
        }

        func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
            guard let url = urls.first else {
                onCompletion(.failure(CSVDocumentPickerError.emptySelection))
                return
            }
            onCompletion(.success(url))
        }

        func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
            onCompletion(.failure(CSVDocumentPickerError.cancelled))
        }
    }
}
#endif

private struct CSVPreparedImport: Sendable {
    let data: Data
    let preview: CSVImportPreview
    let preset: CSVPreset
}

private struct LabelManagementView: View {
    @Environment(\.dismiss) private var dismiss
    @Bindable var model: CashRunwayAppModel
    @State private var isEditorPresented = false
    @State private var labelDraft = CashRunwayLabel(id: UUID(), name: "", colorHex: "#60788A", createdAt: .now, updatedAt: .now)

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
                        labelDraft = CashRunwayLabel(id: UUID(), name: "", colorHex: "#60788A", createdAt: .now, updatedAt: .now)
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
    @Bindable var model: CashRunwayAppModel
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
    @Bindable var model: CashRunwayAppModel
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
                                .foregroundStyle(CashRunwayTheme.textSecondary)
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
    @Bindable var model: CashRunwayAppModel
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
    @Bindable var model: CashRunwayAppModel

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

private struct CSVImportReviewView: View {
    @Environment(\.dismiss) private var dismiss
    @Bindable var model: CashRunwayAppModel
    let preview: CSVImportPreview
    let preset: CSVPreset
    let fileName: String
    let data: Data
    @Binding var mapping: CSVImportMapping
    let isPreparing: Bool
    let preparationProgress: Double
    let preparationStatus: String
    let preparationError: String?
    @State private var importResult: CSVImportResult?
    @State private var importError: String?
    @State private var isImporting = false
    @State private var isAdvancedMappingExpanded = false

    var body: some View {
        NavigationStack {
            Form {
                Section("Source") {
                    summaryRow("File", value: fileName)
                    if !isPreparing, preparationError == nil {
                        summaryRow("Format", value: presetDisplayName)
                        summaryRow("Rows", value: "\(preview.totalRows)")
                    }
                }

                if isPreparing {
                    loadingSection
                } else if let preparationError {
                    Section("Import Error") {
                        Text(preparationError)
                            .foregroundStyle(CashRunwayTheme.negative)
                    }
                } else {
                    if let importResult {
                        resultSection(importResult)
                    } else if let importError {
                        Section("Import Error") {
                            Text(importError)
                                .foregroundStyle(CashRunwayTheme.negative)
                        }
                    }

                    if isImporting {
                        Section("Importing") {
                            ProgressView("Importing transactions...")
                        }
                    }

                    if preset == .cashRunwayWallet {
                        Section("Detected") {
                            summaryRow("Income / Expense", value: typeSummary)
                            summaryRow("Wallet", value: walletSummary)
                            summaryRow("Categories", value: mapping.categoryColumn == nil ? "Fallback category" : "Matched or created from CSV names")
                            summaryRow("Labels", value: mapping.labelsColumn == nil ? "Not imported" : "Matched to existing names")
                        }

                        Section {
                            walletPicker(title: "Fallback Wallet")
                        } header: {
                            Text("Import Settings")
                        } footer: {
                            Text("Used when the CSV wallet is empty or does not match an existing wallet.")
                        }
                    } else {
                        Section(requiredMappingTitle) {
                            Text(requiredMappingMessage)
                                .font(.footnote)
                                .foregroundStyle(hasRequiredMapping ? CashRunwayTheme.textSecondary : CashRunwayTheme.negative)
                            requiredPicker("Date", selection: $mapping.dateColumn)
                            amountPickers
                        }

                        Section {
                            DisclosureGroup("Advanced Mapping", isExpanded: $isAdvancedMappingExpanded) {
                                walletPicker(title: "Fallback Wallet")
                                Picker("Default Kind", selection: $mapping.defaultKind) {
                                    Text("Expense").tag(TransactionDraft.Kind.expense)
                                    Text("Income").tag(TransactionDraft.Kind.income)
                                }
                                optionalPicker("Type", selection: $mapping.typeColumn)
                                optionalPicker("Wallet", selection: $mapping.walletColumn)
                                optionalPicker("Currency", selection: $mapping.currencyColumn)
                                optionalPicker("Merchant", selection: $mapping.merchantColumn)
                                optionalPicker("Note", selection: $mapping.noteColumn)
                                optionalPicker("Category", selection: $mapping.categoryColumn)
                                optionalPicker("Labels", selection: $mapping.labelsColumn)
                            }
                        }
                    }

                    if !reviewRows.isEmpty {
                        Section("Preview") {
                            ForEach(reviewRows) { row in
                                CSVImportPreviewRowView(row: row)
                                    .padding(.vertical, 4)
                            }
                        }
                    }
                }
            }
            .navigationTitle("Import CSV")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(importResult == nil && preparationError == nil ? "Cancel" : "Done") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    if !isPreparing, preparationError == nil, importResult == nil {
                        Button("Import") {
                            startImport()
                        }
                        .disabled(!hasRequiredMapping || isImporting)
                    }
                }
            }
        }
    }

    private var presetDisplayName: String {
        preset == .cashRunwayWallet ? "Cash Runway Wallet CSV" : preset.rawValue
    }

    private var hasRequiredMapping: Bool {
        !mapping.dateColumn.isEmpty && (mapping.amountColumn != nil || mapping.debitColumn != nil || mapping.creditColumn != nil)
    }

    private var requiredMappingTitle: String {
        hasRequiredMapping ? "Ready To Import" : "Needs Mapping"
    }

    private var requiredMappingMessage: String {
        hasRequiredMapping ? "Required fields are mapped." : "Select a date and amount source."
    }

    private var defaultKindName: String {
        mapping.defaultKind == .income ? "Income" : "Expense"
    }

    private var typeSummary: String {
        if let typeColumn = mapping.typeColumn {
            "From \(typeColumn) column"
        } else {
            "Default \(defaultKindName)"
        }
    }

    private var selectedWalletName: String {
        model.wallets.first(where: { $0.id == mapping.walletID })?.name ?? "Selected wallet"
    }

    private var walletSummary: String {
        if mapping.walletColumn != nil {
            "CSV names; unmatched use \(selectedWalletName)"
        } else {
            "All rows use \(selectedWalletName)"
        }
    }

    private var boundedPreparationProgress: Double {
        min(max(preparationProgress, 0.0), 1.0)
    }

    private var amountPickers: some View {
        Group {
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
        }
    }

    private var reviewRows: [CSVImportReviewRow] {
        let headerIndex = Dictionary(uniqueKeysWithValues: preview.headers.enumerated().map { ($1, $0) })
        return preview.sampleRows.prefix(3).enumerated().map { offset, row in
            let signedAmount = previewAmount(row: row, headerIndex: headerIndex)
            let kind = previewKind(row: row, headerIndex: headerIndex, signedAmount: signedAmount)
            let displayMinor = previewDisplayAmount(signedAmount: signedAmount, kind: kind)
            let rawAmount = firstNonEmptyCell(row, columns: [mapping.amountColumn, mapping.debitColumn, mapping.creditColumn], headerIndex: headerIndex)
            return CSVImportReviewRow(
                id: offset,
                date: cell(row, mapping.dateColumn, headerIndex),
                amount: displayMinor.map(MoneyFormatter.string(from:)) ?? rawAmount,
                amountColor: displayMinor.map(CashRunwayTheme.amountColor) ?? (kind == .income ? CashRunwayTheme.positive : CashRunwayTheme.negative),
                title: firstNonEmptyCell(row, columns: [mapping.categoryColumn, mapping.noteColumn, mapping.merchantColumn], headerIndex: headerIndex).ifEmpty("Uncategorized"),
                subtitle: cell(row, mapping.walletColumn, headerIndex).ifEmpty(selectedWalletName)
            )
        }
    }

    private func resultSection(_ result: CSVImportResult) -> some View {
        Section("Result") {
            SwiftUI.Label("Imported \(result.insertedTransactions) transactions", systemImage: "checkmark.circle.fill")
                .foregroundStyle(CashRunwayTheme.positive)
            if result.job.invalidRows > 0 {
                Text("\(result.job.invalidRows) rows skipped")
                    .foregroundStyle(CashRunwayTheme.negative)
                ForEach(result.rowErrors) { rowError in
                    Text("Row \(rowError.rowNumber): \(rowError.message)")
                        .font(.footnote)
                        .foregroundStyle(CashRunwayTheme.textSecondary)
                }
            }
        }
    }

    private var loadingSection: some View {
        Section("Loading") {
            VStack(alignment: .leading, spacing: 10) {
                ProgressView(value: boundedPreparationProgress)
                    .progressViewStyle(.linear)
                Text(preparationStatus.ifEmpty("Reading CSV..."))
                    .font(.footnote)
                    .foregroundStyle(CashRunwayTheme.textSecondary)
            }
            .padding(.vertical, 4)
        }
    }

    private func startImport() {
        guard !isImporting else { return }
        importError = nil
        isImporting = true
        Task { @MainActor in
            await Task.yield()
            do {
                importResult = try model.importCSV(data: data, fileName: fileName, mapping: mapping)
            } catch {
                importError = error.localizedDescription
            }
            isImporting = false
        }
    }

    private func summaryRow(_ title: String, value: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
                .foregroundStyle(CashRunwayTheme.textSecondary)
            Spacer(minLength: 16)
            Text(value)
                .multilineTextAlignment(.trailing)
                .foregroundStyle(CashRunwayTheme.textPrimary)
        }
    }

    private func walletPicker(title: String) -> some View {
        Picker(title, selection: $mapping.walletID) {
            ForEach(model.wallets) { wallet in
                Text(wallet.name).tag(wallet.id)
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

    private func cell(_ row: [String], _ column: String?, _ headerIndex: [String: Int]) -> String {
        guard let column, let index = headerIndex[column], row.indices.contains(index) else { return "" }
        return row[index]
    }

    private func firstNonEmptyCell(_ row: [String], columns: [String?], headerIndex: [String: Int]) -> String {
        columns.lazy.map { cell(row, $0, headerIndex).trimmingCharacters(in: .whitespacesAndNewlines) }.first { !$0.isEmpty } ?? ""
    }

    private func previewAmount(row: [String], headerIndex: [String: Int]) -> Int64? {
        if let amountColumn = mapping.amountColumn {
            return try? MoneyFormatter.parseMinorUnits(cell(row, amountColumn, headerIndex))
        }
        let debit = try? MoneyFormatter.parseMinorUnits(cell(row, mapping.debitColumn, headerIndex))
        let credit = try? MoneyFormatter.parseMinorUnits(cell(row, mapping.creditColumn, headerIndex))
        if let debit, debit != 0 { return -abs(debit) }
        if let credit, credit != 0 { return abs(credit) }
        return nil
    }

    private func previewKind(row: [String], headerIndex: [String: Int], signedAmount: Int64?) -> TransactionDraft.Kind {
        let raw = cell(row, mapping.typeColumn, headerIndex).lowercased()
        if raw == "income" || raw == "inflow" || raw == "credit" {
            return .income
        }
        if raw == "expense" || raw == "outflow" || raw == "debit" {
            return .expense
        }
        if let signedAmount, signedAmount < 0 {
            return .expense
        }
        if let signedAmount, signedAmount > 0, mapping.typeColumn != nil {
            return .income
        }
        return mapping.defaultKind
    }

    private func previewDisplayAmount(signedAmount: Int64?, kind: TransactionDraft.Kind) -> Int64? {
        guard let signedAmount else { return nil }
        if kind == .expense, signedAmount > 0 {
            return -signedAmount
        }
        if kind == .income, signedAmount < 0 {
            return abs(signedAmount)
        }
        return signedAmount
    }
}

private struct CSVImportReviewRow: Identifiable {
    let id: Int
    let date: String
    let amount: String
    let amountColor: Color
    let title: String
    let subtitle: String
}

private struct CSVImportPreviewRowView: View {
    let row: CSVImportReviewRow

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(row.title)
                    .font(.body.weight(.medium))
                    .foregroundStyle(CashRunwayTheme.textPrimary)
                HStack(spacing: 6) {
                    Text(row.date)
                    Text(row.subtitle)
                }
                .font(.footnote)
                .foregroundStyle(CashRunwayTheme.textSecondary)
            }
            Spacer(minLength: 12)
            Text(row.amount)
                .font(.body.weight(.semibold))
                .foregroundStyle(row.amountColor)
                .multilineTextAlignment(.trailing)
        }
    }
}

private extension String {
    func ifEmpty(_ fallback: String) -> String {
        isEmpty ? fallback : self
    }
}
