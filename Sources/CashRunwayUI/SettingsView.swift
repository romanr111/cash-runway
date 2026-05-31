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
    @State private var isMonobankConnectionPresented = false
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
    @State private var isExporterPresented = false
    @State private var exportFileURL: URL?
    @State private var isExporting = false
    @State private var isBackupExportWarningPresented = false
    @State private var isBackupExporterPresented = false
    @State private var backupExportFileURL: URL?
    @State private var isBackupExporting = false
    @State private var isBackupImporterPresented = false
    @State private var isBackupImportReviewPresented = false
    @State private var backupImportData = Data()
    @State private var backupImportFileName = ""
    @State private var backupImportSummary: BackupValidationSummary?
    @State private var backupImportPreparationError: String?

    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 24) {
                    ScreenTitle(title: "More")

                    moreStatusCard

                    operationSection("Manage") {
                        operationButton(icon: "square.grid.2x2", tint: CashRunwayTheme.manageTint, title: "Categories", subtitle: "Visibility, order, icons, and merges", trailing: "\(model.expenseCategories.count + model.incomeCategories.count)") {
                            isCategoryManagementPresented = true
                        }
                        rowDivider
                        operationButton(icon: "tag.fill", tint: CashRunwayTheme.warning, title: "Labels", subtitle: "Organize cross-category transaction groups", trailing: "\(model.labels.count)") {
                            isLabelsPresented = true
                        }
                        rowDivider
                        operationButton(icon: "repeat", tint: CashRunwayTheme.accent, title: "Scheduled Transactions", subtitle: "Recurring templates and upcoming occurrences", trailing: "\(model.templates.count)") {
                            isTemplatesPresented = true
                        }
                        rowDivider
                        operationButton(icon: "wallet.pass.fill", tint: CashRunwayTheme.textSecondary, title: "Manual Wallets", subtitle: "Cash, card, and account balances", trailing: "\(model.wallets.count)") {
                            isWalletsPresented = true
                        }
                        rowDivider
                        OperationRow(icon: "banknote.fill", tint: CashRunwayTheme.dataTint, title: "Main Currency", subtitle: "Used for all totals and imports", trailing: "UAH", showsChevron: false)
                    }

                    operationSection("Data Safety") {
                        operationButton(icon: "tray.and.arrow.down.fill", tint: CashRunwayTheme.dataTint, title: "Import CSV", subtitle: "Map and load bank exports", trailing: nil) {
                            if model.hasBootstrapped && model.wallets.isEmpty {
                                model.errorMessage = "Create at least one wallet before importing CSV."
                            } else {
                                isImporterPresented = true
                            }
                        }
                        rowDivider
                        operationButton(icon: "square.and.arrow.up.fill", tint: CashRunwayTheme.warning, title: "Export CSV", subtitle: isExporting ? "Exporting..." : "Share the current filtered export", trailing: nil) {
                            guard !isExporting else { return }
                            isExporting = true
                            let service = model.csvService
                            let query = model.transactionQuery
                            Task.detached(priority: .userInitiated) {
                                do {
                                    let csv = try service.exportCSV(query: query)
                                    let url = FileManager.default.temporaryDirectory.appendingPathComponent("cash-runway-export.csv")
                                    try csv.write(to: url, atomically: true, encoding: .utf8)
                                    await MainActor.run {
                                        exportFileURL = url
                                        isExporterPresented = true
                                        isExporting = false
                                    }
                                } catch {
                                    await MainActor.run {
                                        model.errorMessage = error.localizedDescription
                                        isExporting = false
                                    }
                                }
                            }
                        }
                        rowDivider
                        operationButton(icon: "externaldrive.fill", tint: CashRunwayTheme.safetyTint, title: "Import Full Backup", subtitle: "Replace local data from JSON", trailing: nil) {
                            isBackupImporterPresented = true
                        }
                        rowDivider
                        operationButton(icon: "externaldrive.badge.plus", tint: CashRunwayTheme.safetyTint, title: "Export Full Backup", subtitle: isBackupExporting ? "Exporting..." : "Share unencrypted backup JSON", trailing: nil) {
                            guard !isBackupExporting else { return }
                            isBackupExportWarningPresented = true
                        }
                    }

                    operationSection("Connections") {
                        operationButton(icon: "creditcard.fill", tint: CashRunwayTheme.accent, title: "Monobank", subtitle: monobankSubtitle, trailing: monobankStatusLabel) {
                            isMonobankConnectionPresented = true
                        }
                        .accessibilityIdentifier(CashRunwayAccessibilityID.settingsMonobankRow)
                    }

                    #if DEBUG
                    operationSection("Debug") {
                        operationButton(icon: "wrench.and.screwdriver.fill", tint: CashRunwayTheme.negative, title: "Diagnostics", subtitle: "Counts and local state", trailing: nil) {
                            isDiagnosticsPresented = true
                        }
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
            .sheet(isPresented: $isMonobankConnectionPresented) {
                MonobankConnectionView(model: model)
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
            .sheet(isPresented: $isExporterPresented) {
                if let url = exportFileURL {
                    #if canImport(UIKit)
                    ActivityView(activityItems: [url])
                    #else
                    Text("CSV export is unavailable on this platform.")
                    #endif
                }
            }
            .sheet(isPresented: $isBackupExporterPresented) {
                if let url = backupExportFileURL {
                    #if canImport(UIKit)
                    ActivityView(activityItems: [url])
                    #else
                    Text("Backup export is unavailable on this platform.")
                    #endif
                }
            }
            .sheet(isPresented: $isImporterPresented) {
                #if canImport(UIKit)
                DocumentPicker(allowedContentTypes: [.commaSeparatedText, .plainText]) { result in
                    handleImporterResult(result)
                }
                #else
                Text("CSV import is unavailable on this platform.")
                #endif
            }
            .sheet(isPresented: $isBackupImporterPresented) {
                #if canImport(UIKit)
                DocumentPicker(allowedContentTypes: [.json, .plainText]) { result in
                    handleBackupImporterResult(result)
                }
                #else
                Text("Backup import is unavailable on this platform.")
                #endif
            }
            .sheet(isPresented: $isBackupImportReviewPresented) {
                BackupImportReviewView(
                    model: model,
                    fileName: backupImportFileName,
                    data: backupImportData,
                    summary: backupImportSummary,
                    preparationError: backupImportPreparationError
                )
            }
            .alert("Unencrypted Backup", isPresented: $isBackupExportWarningPresented) {
                Button("Cancel", role: .cancel) {}
                Button("Export") {
                    exportFullBackup()
                }
            } message: {
                Text("This backup file contains unencrypted financial data. Anyone with access to it may be able to read your wallets, transactions, categories, labels, and recurring entries. Store it securely.")
            }
        }
    }

    private var moreStatusCard: some View {
        CashRunwaySurface {
            VStack(alignment: .leading, spacing: 16) {
                HStack(alignment: .top, spacing: 14) {
                    ZStack {
                        Circle()
                            .fill(CashRunwayTheme.accentMuted)
                        Image(systemName: "chart.line.uptrend.xyaxis")
                            .font(.system(size: 23, weight: .semibold))
                            .foregroundStyle(CashRunwayTheme.accentDark)
                    }
                    .frame(width: 54, height: 54)

                    VStack(alignment: .leading, spacing: 4) {
                        Text("Operations")
                            .font(CashRunwayTheme.headingFont)
                            .foregroundStyle(CashRunwayTheme.textPrimary)
                        Text("Manage structure, connected accounts, and local data files.")
                            .font(CashRunwayTheme.bodyFont)
                            .foregroundStyle(CashRunwayTheme.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                HStack(spacing: 10) {
                    statusMetric("Wallets", "\(model.wallets.count)")
                    statusMetric("Bank Sync", monobankStatusLabel)
                }
            }
        }
    }

    private func statusMetric(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(value)
                .font(.system(size: 18, weight: .bold, design: .rounded))
                .foregroundStyle(CashRunwayTheme.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
            Text(title)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(CashRunwayTheme.textMuted)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(CashRunwayTheme.pill, in: RoundedRectangle(cornerRadius: CashRunwayTheme.radiusS, style: .continuous))
    }

    private func operationSection<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(CashRunwayTheme.textMuted)
                .textCase(.uppercase)
                .padding(.horizontal, 4)

            VStack(spacing: 0) {
                content()
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(CashRunwayTheme.surface, in: RoundedRectangle(cornerRadius: CashRunwayTheme.radiusL, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: CashRunwayTheme.radiusL, style: .continuous).stroke(CashRunwayTheme.line, lineWidth: 1))
            .shadow(color: CashRunwayTheme.softShadow, radius: 10, y: 3)
        }
    }

    private func operationButton(
        icon: String,
        tint: Color,
        title: String,
        subtitle: String,
        trailing: String?,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            OperationRow(icon: icon, tint: tint, title: title, subtitle: subtitle, trailing: trailing)
        }
        .buttonStyle(.plain)
    }

    private func handleImporterResult(_ result: Result<URL, any Error>) {
        isImporterPresented = false
        switch result {
        case let .success(url):
            prepareImport(from: url)
        case let .failure(error):
            if let pickerError = error as? DocumentPickerError, pickerError == .cancelled {
                return
            }
            model.errorMessage = error.localizedDescription
        }
    }

    private func exportFullBackup() {
        isBackupExporting = true
        let service = model.backupService
        Task { @MainActor in
            do {
                let data = try await Task.detached(priority: .userInitiated) {
                    let backup = try service.exportFullBackup()
                    return try service.encode(backup)
                }.value
                let url = FileManager.default.temporaryDirectory.appendingPathComponent("cash-runway-backup-\(backupFileTimestamp()).json")
                try data.write(to: url, options: .atomic)
                backupExportFileURL = url
                isBackupExporterPresented = true
            } catch {
                model.errorMessage = error.localizedDescription
            }
            isBackupExporting = false
        }
    }

    private func handleBackupImporterResult(_ result: Result<URL, any Error>) {
        isBackupImporterPresented = false
        switch result {
        case let .success(url):
            prepareBackupImport(from: url)
        case let .failure(error):
            if let pickerError = error as? DocumentPickerError, pickerError == .cancelled {
                return
            }
            model.errorMessage = error.localizedDescription
        }
    }

    private func prepareBackupImport(from url: URL) {
        let fileName = url.lastPathComponent.isEmpty ? "backup.json" : url.lastPathComponent
        let service = model.backupService
        backupImportData = Data()
        backupImportFileName = fileName
        backupImportSummary = nil
        backupImportPreparationError = nil
        isBackupImportReviewPresented = true

        Task {
            do {
                let data = try await Task.detached(priority: .userInitiated) {
                    try CSVImportFileReader.readData(from: url)
                }.value
                let summary = try await Task.detached(priority: .userInitiated) {
                    let backup = try service.decode(data: data)
                    return try service.validate(backup)
                }.value

                await MainActor.run {
                    backupImportData = data
                    backupImportSummary = summary
                }
            } catch {
                await MainActor.run {
                    backupImportPreparationError = error.localizedDescription
                }
            }
        }
    }

    private func backupFileTimestamp() -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd-HHmmss"
        return formatter.string(from: Date())
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

    private var monobankSubtitle: String {
        let status = model.monobankConnectionStatus()
        guard let integration = status.integration, integration.status != .disabled else {
            return "Connect cards and import new expenses automatically"
        }
        if integration.status == .tokenInvalid || integration.status == .syncFailed || status.lastSyncError != nil {
            return "Sync failed · Tap to fix"
        }
        if let lastSync = status.lastSuccessfulSyncAt {
            return "\(status.enabledAccountCount) cards connected · Last sync \(relativeFormatter.localizedString(for: lastSync, relativeTo: Date()))"
        }
        return "\(status.enabledAccountCount) cards connected · Waiting for first sync"
    }

    private var monobankStatusLabel: String {
        let status = model.monobankConnectionStatus()
        guard let integration = status.integration, integration.status != .disabled else {
            return "Off"
        }
        if integration.status == .tokenInvalid || integration.status == .syncFailed || status.lastSyncError != nil {
            return "Fix"
        }
        return "On"
    }

    private var relativeFormatter: RelativeDateTimeFormatter {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        return formatter
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
        // Import CSV is blocked at the UI level when no wallets exist.
        guard let walletID = model.wallets.first?.id else {
            // UI blocks CSV import when wallets are empty; this is a safety net
            return CSVImportMapping(
                dateColumn: headers.first ?? "",
                amountColumn: nil,
                debitColumn: nil,
                creditColumn: nil,
                merchantColumn: nil,
                noteColumn: nil,
                categoryColumn: nil,
                labelsColumn: nil,
                walletID: nil,
                defaultKind: .expense,
                typeColumn: nil,
                walletColumn: nil,
                currencyColumn: nil,
                authorColumn: nil
            )
        }
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

private enum DocumentPickerError: LocalizedError, Equatable {
    case emptySelection
    case cancelled

    var errorDescription: String? {
        switch self {
        case .emptySelection:
            "No file was selected."
        case .cancelled:
            nil
        }
    }
}

#if canImport(UIKit)
private struct ActivityView: UIViewControllerRepresentable {
    let activityItems: [Any]
    let applicationActivities: [UIActivity]? = nil

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: activityItems, applicationActivities: applicationActivities)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

private struct DocumentPicker: UIViewControllerRepresentable {
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
                onCompletion(.failure(DocumentPickerError.emptySelection))
                return
            }
            onCompletion(.success(url))
        }

        func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
            onCompletion(.failure(DocumentPickerError.cancelled))
        }
    }
}
#endif

private struct CSVPreparedImport: Sendable {
    let data: Data
    let preview: CSVImportPreview
    let preset: CSVPreset
}

private struct BackupImportReviewView: View {
    @Environment(\.dismiss) private var dismiss
    @Bindable var model: CashRunwayAppModel
    let fileName: String
    let data: Data
    let summary: BackupValidationSummary?
    let preparationError: String?
    @State private var isRestoreConfirmationPresented = false
    @State private var isRestoring = false
    @State private var restoreMessage: String?
    @State private var restoreError: String?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    backupFlowHeader
                }
                .listRowBackground(CashRunwayTheme.surface)

                Section("Source") {
                    summaryRow("File", value: fileName)
                }

                if let preparationError {
                    Section("Import Error") {
                        Text(preparationError)
                            .foregroundStyle(CashRunwayTheme.negative)
                    }
                } else if let summary {
                    Section("Preview") {
                        summaryRow("Backup created", value: Self.dateFormatter.string(from: summary.createdAt))
                        summaryRow("Wallets", value: "\(summary.walletCount)")
                        summaryRow("Transactions", value: "\(summary.transactionCount)")
                        summaryRow("Categories", value: "\(summary.categoryCount)")
                        summaryRow("Labels", value: "\(summary.labelCount)")
                        summaryRow("Recurring templates", value: "\(summary.recurringTemplateCount)")
                    }

                    Section {
                        Text("Restoring this backup will replace all current Cash Runway data on this device. This cannot be merged automatically.")
                            .foregroundStyle(CashRunwayTheme.negative)
                    }

                    if isRestoring {
                        Section("Restoring") {
                            ProgressView("Restoring backup...")
                        }
                    }

                    if let restoreMessage {
                        Section("Result") {
                            Text(restoreMessage)
                                .foregroundStyle(CashRunwayTheme.positive)
                        }
                    } else if let restoreError {
                        Section("Restore Error") {
                            Text(restoreError)
                                .foregroundStyle(CashRunwayTheme.negative)
                        }
                    }
                } else {
                    Section("Loading") {
                        ProgressView("Reading backup...")
                    }
                }
            }
            .navigationTitle("Import Full Backup")
            .scrollContentBackground(.hidden)
            .background(CashRunwayTheme.background)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(restoreMessage == nil && preparationError == nil ? "Cancel" : "Done") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    if summary != nil, preparationError == nil, restoreMessage == nil {
                        Button("Restore", role: .destructive) {
                            isRestoreConfirmationPresented = true
                        }
                        .disabled(isRestoring)
                    }
                }
            }
            .alert("Replace Current Data?", isPresented: $isRestoreConfirmationPresented) {
                Button("Cancel", role: .cancel) {}
                Button("Restore", role: .destructive) {
                    startRestore()
                }
            } message: {
                Text("Restoring this backup will replace all current Cash Runway data on this device. This cannot be merged automatically.")
            }
        }
    }

    private var backupFlowHeader: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                Image(systemName: "externaldrive.fill")
                    .font(.system(size: 24, weight: .semibold))
                    .foregroundStyle(CashRunwayTheme.safetyTint)
                    .frame(width: 48, height: 48)
                    .background(CashRunwayTheme.safetyTint.opacity(0.14), in: Circle())
                VStack(alignment: .leading, spacing: 4) {
                    Text("Full Backup Restore")
                        .font(CashRunwayTheme.headingFont)
                        .foregroundStyle(CashRunwayTheme.textPrimary)
                    Text("Review the file summary before replacing local data.")
                        .font(CashRunwayTheme.bodyFont)
                        .foregroundStyle(CashRunwayTheme.textSecondary)
                }
            }
            HStack(spacing: 8) {
                flowPill("Source", isActive: true)
                flowPill("Preview", isActive: summary != nil)
                flowPill("Restore", isActive: restoreMessage != nil)
            }
        }
        .padding(.vertical, 6)
    }

    private func startRestore() {
        guard !isRestoring else { return }
        isRestoring = true
        restoreError = nil
        Task { @MainActor in
            do {
                _ = try await model.restoreFullBackup(data: data)
                restoreMessage = "Backup restored successfully."
            } catch {
                restoreError = "Backup could not be restored. Your current data was not changed."
            }
            isRestoring = false
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

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter
    }()
}

private struct LabelManagementView: View {
    @Environment(\.dismiss) private var dismiss
    @Bindable var model: CashRunwayAppModel
    @State private var isEditorPresented = false
    @State private var labelDraft = CashRunwayLabel(id: UUID(), name: "", colorHex: "#60788A", createdAt: .now, updatedAt: .now)

    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 18) {
                    managementHeader(
                        title: "Labels",
                        subtitle: "\(model.labels.count) saved labels",
                        icon: "tag.fill",
                        tint: CashRunwayTheme.warning
                    )

                    if model.labels.isEmpty {
                        ContentUnavailableView(
                            "No Labels",
                            systemImage: "tag.fill",
                            description: Text("Add labels to group transactions across categories.")
                        )
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 44)
                    } else {
                        LazyVStack(spacing: 10) {
                            ForEach(model.labels) { label in
                                Button {
                                    labelDraft = label
                                    isEditorPresented = true
                                } label: {
                                    HStack(spacing: 14) {
                                        Circle()
                                            .fill(CashRunwayTheme.categoryColor(label.colorHex))
                                            .frame(width: 18, height: 18)
                                            .frame(width: 48, height: 48)
                                            .background(CashRunwayTheme.pill, in: Circle())

                                        Text(label.name)
                                            .font(CashRunwayTheme.subheadingFont)
                                            .foregroundStyle(CashRunwayTheme.textPrimary)
                                            .lineLimit(1)
                                            .truncationMode(.tail)

                                        Spacer()

                                        Image(systemName: "pencil")
                                            .font(.system(size: 14, weight: .semibold))
                                            .foregroundStyle(CashRunwayTheme.textMuted)
                                    }
                                    .ledgerSurface(cornerRadius: CashRunwayTheme.radiusM)
                                }
                                .buttonStyle(.plain)
                                .swipeActions(edge: .trailing) {
                                    Button(role: .destructive) {
                                        model.deleteLabel(id: label.id)
                                    } label: {
                                        SwiftUI.Label("Delete", systemImage: "trash")
                                    }
                                }
                            }
                        }
                    }
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 16)
                .padding(.bottom, 92)
            }
            .background(CashRunwayTheme.background)
            .navigationTitle("Labels")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Done") { dismiss() }
                }
            }
            .safeAreaInset(edge: .bottom) {
                addBar(title: "Add Label", systemImage: "plus") {
                    labelDraft = CashRunwayLabel(id: UUID(), name: "", colorHex: CategoryAppearanceCatalog.defaultColor, createdAt: .now, updatedAt: .now)
                    isEditorPresented = true
                }
            }
            .sheet(isPresented: $isEditorPresented) {
                LabelEditorView(model: model, label: $labelDraft)
            }
        }
    }

    private func managementHeader(title: String, subtitle: String, icon: String, tint: Color) -> some View {
        HStack(spacing: 14) {
            ZStack {
                Circle().fill(tint.opacity(0.14))
                Image(systemName: icon)
                    .font(.system(size: 21, weight: .semibold))
                    .foregroundStyle(tint)
            }
            .frame(width: 54, height: 54)

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(CashRunwayTheme.headingFont)
                    .foregroundStyle(CashRunwayTheme.textPrimary)
                Text(subtitle)
                    .font(CashRunwayTheme.bodyFont)
                    .foregroundStyle(CashRunwayTheme.textSecondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct WalletManagementView: View {
    @Environment(\.dismiss) private var dismiss
    @Bindable var model: CashRunwayAppModel
    @State private var isEditorPresented = false
    @State private var walletDraft = Wallet(id: UUID(), name: "", kind: .cash, colorHex: "#60788A", iconName: "wallet.pass.fill", startingBalanceMinor: 0, currentBalanceMinor: 0, isArchived: false, sortOrder: 0, createdAt: .now, updatedAt: .now)

    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 18) {
                    managementHeader(
                        title: "Manual Wallets",
                        subtitle: "\(model.wallets.count) wallets · \(MoneyFormatter.string(from: model.overviewSnapshot?.totalWealthMinor ?? 0)) total",
                        icon: "wallet.pass.fill",
                        tint: CashRunwayTheme.textSecondary
                    )

                    if model.wallets.isEmpty {
                        ContentUnavailableView(
                            "No Wallets",
                            systemImage: "wallet.pass.fill",
                            description: Text("Create a wallet before adding transactions or imports.")
                        )
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 44)
                    } else {
                        LazyVStack(spacing: 10) {
                            ForEach(model.wallets) { wallet in
                                Button {
                                    walletDraft = wallet
                                    isEditorPresented = true
                                } label: {
                                    HStack(spacing: 14) {
                                        CategoryGlyph(iconName: wallet.iconName ?? "wallet.pass.fill", colorHex: wallet.colorHex ?? "#60788A", size: 50)
                                        VStack(alignment: .leading, spacing: 3) {
                                            Text(wallet.name)
                                                .font(CashRunwayTheme.subheadingFont)
                                                .foregroundStyle(CashRunwayTheme.textPrimary)
                                                .lineLimit(1)
                                            Text(wallet.kind.rawValue.capitalized)
                                                .font(CashRunwayTheme.captionFont)
                                                .foregroundStyle(CashRunwayTheme.textSecondary)
                                        }
                                        Spacer()
                                        Text(MoneyFormatter.string(from: wallet.currentBalanceMinor))
                                            .font(.system(size: 16, weight: .semibold, design: .rounded))
                                            .foregroundStyle(wallet.currentBalanceMinor < 0 ? CashRunwayTheme.negative : CashRunwayTheme.textPrimary)
                                            .lineLimit(1)
                                            .minimumScaleFactor(0.75)
                                        Image(systemName: "pencil")
                                            .font(.system(size: 14, weight: .semibold))
                                            .foregroundStyle(CashRunwayTheme.textMuted)
                                    }
                                    .ledgerSurface(cornerRadius: CashRunwayTheme.radiusM)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 16)
                .padding(.bottom, 92)
            }
            .background(CashRunwayTheme.background)
            .navigationTitle("Manual Wallets")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Done") { dismiss() }
                }
            }
            .safeAreaInset(edge: .bottom) {
                addBar(title: "Add Wallet", systemImage: "plus") {
                    walletDraft = Wallet(id: UUID(), name: "", kind: .cash, colorHex: "#60788A", iconName: "wallet.pass.fill", startingBalanceMinor: 0, currentBalanceMinor: 0, isArchived: false, sortOrder: model.wallets.count, createdAt: .now, updatedAt: .now)
                    isEditorPresented = true
                }
            }
            .sheet(isPresented: $isEditorPresented) {
                WalletEditorView(model: model, wallet: $walletDraft)
            }
        }
    }

    private func managementHeader(title: String, subtitle: String, icon: String, tint: Color) -> some View {
        HStack(spacing: 14) {
            ZStack {
                Circle().fill(tint.opacity(0.14))
                Image(systemName: icon)
                    .font(.system(size: 21, weight: .semibold))
                    .foregroundStyle(tint)
            }
            .frame(width: 54, height: 54)

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(CashRunwayTheme.headingFont)
                    .foregroundStyle(CashRunwayTheme.textPrimary)
                Text(subtitle)
                    .font(CashRunwayTheme.bodyFont)
                    .foregroundStyle(CashRunwayTheme.textSecondary)
                    .lineLimit(2)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct ScheduledTransactionsView: View {
    @Environment(\.dismiss) private var dismiss
    @Bindable var model: CashRunwayAppModel
    @State private var templateDraft = RecurringTemplate(
        id: UUID(),
        kind: .expense,
        walletID: UUID(),
        counterpartyWalletID: nil,
        amountMinor: 0,
        categoryID: nil,
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
    @State private var isEditorPresented = false

    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 18) {
                    managementHeader

                    managementSection("Templates", count: model.templates.count) {
                        if model.templates.isEmpty {
                            Text("No recurring templates yet.")
                                .font(CashRunwayTheme.bodyFont)
                                .foregroundStyle(CashRunwayTheme.textSecondary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.vertical, 10)
                        } else {
                            ForEach(model.templates) { template in
                                Button {
                                    templateDraft = template
                                    isEditorPresented = true
                                } label: {
                                    scheduledTemplateRow(template)
                                }
                                .buttonStyle(.plain)
                                if template.id != model.templates.last?.id {
                                    Divider().overlay(CashRunwayTheme.line)
                                }
                            }
                        }
                    }

                    managementSection("Upcoming", count: model.instances.count) {
                        if model.instances.isEmpty {
                            Text("No scheduled occurrences.")
                                .font(CashRunwayTheme.bodyFont)
                                .foregroundStyle(CashRunwayTheme.textSecondary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.vertical, 10)
                        } else {
                            ForEach(model.instances) { instance in
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(instance.dueDate.formatted(date: .abbreviated, time: .omitted))
                                        .font(CashRunwayTheme.subheadingFont)
                                        .foregroundStyle(CashRunwayTheme.textPrimary)
                                    Text(instance.status.rawValue.capitalized)
                                        .font(CashRunwayTheme.captionFont)
                                        .foregroundStyle(CashRunwayTheme.textSecondary)
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.vertical, 10)
                                if instance.id != model.instances.last?.id {
                                    Divider().overlay(CashRunwayTheme.line)
                                }
                            }
                        }
                    }
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 16)
                .padding(.bottom, 92)
            }
            .background(CashRunwayTheme.background)
            .navigationTitle("Scheduled Transactions")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Done") { dismiss() }
                }
            }
            .safeAreaInset(edge: .bottom) {
                addBar(title: "Add Template", systemImage: "plus", isDisabled: model.wallets.isEmpty) {
                    guard let firstWalletID = model.wallets.first?.id else { return }
                    templateDraft = RecurringTemplate(
                        id: UUID(),
                        kind: .expense,
                        walletID: firstWalletID,
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
                }
            }
            .sheet(isPresented: $isEditorPresented) {
                RecurringTemplateEditorView(model: model, template: $templateDraft)
            }
        }
    }

    private var managementHeader: some View {
        HStack(spacing: 14) {
            ZStack {
                Circle().fill(CashRunwayTheme.accentMuted)
                Image(systemName: "repeat")
                    .font(.system(size: 21, weight: .semibold))
                    .foregroundStyle(CashRunwayTheme.accentDark)
            }
            .frame(width: 54, height: 54)
            VStack(alignment: .leading, spacing: 4) {
                Text("Scheduled Transactions")
                    .font(CashRunwayTheme.headingFont)
                    .foregroundStyle(CashRunwayTheme.textPrimary)
                Text("\(model.templates.count) templates · \(model.instances.count) upcoming")
                    .font(CashRunwayTheme.bodyFont)
                    .foregroundStyle(CashRunwayTheme.textSecondary)
            }
        }
    }

    private func managementSection<Content: View>(_ title: String, count: Int, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(title)
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(CashRunwayTheme.textMuted)
                    .textCase(.uppercase)
                Spacer()
                Text("\(count)")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(CashRunwayTheme.textMuted)
            }
            VStack(spacing: 0) {
                content()
            }
            .ledgerSurface(cornerRadius: CashRunwayTheme.radiusL)
        }
    }

    private func scheduledTemplateRow(_ template: RecurringTemplate) -> some View {
        HStack(spacing: 14) {
            ZStack {
                Circle().fill(CashRunwayTheme.accentMuted)
                Image(systemName: template.kind == .transfer ? "arrow.left.arrow.right" : "repeat")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(CashRunwayTheme.accentDark)
            }
            .frame(width: 46, height: 46)

            VStack(alignment: .leading, spacing: 3) {
                Text(template.merchant ?? template.kind.rawValue.capitalized)
                    .font(CashRunwayTheme.subheadingFont)
                    .foregroundStyle(CashRunwayTheme.textPrimary)
                    .lineLimit(1)
                Text("\(template.ruleType.rawValue.capitalized) every \(template.ruleInterval)")
                    .font(CashRunwayTheme.captionFont)
                    .foregroundStyle(CashRunwayTheme.textSecondary)
            }
            Spacer()
            Text(MoneyFormatter.string(from: template.amountMinor))
                .font(.system(size: 16, weight: .semibold, design: .rounded))
                .foregroundStyle(CashRunwayTheme.amountColor(template.kind == .income ? template.amountMinor : -template.amountMinor))
                .lineLimit(1)
        }
        .padding(.vertical, 10)
    }
}

private func addBar(title: String, systemImage: String, isDisabled: Bool = false, action: @escaping () -> Void) -> some View {
    Button(action: action) {
        HStack(spacing: 10) {
            Image(systemName: systemImage)
            Text(title)
        }
        .font(.system(size: 17, weight: .bold))
        .foregroundStyle(.white)
        .frame(maxWidth: .infinity)
        .padding(.vertical, 15)
        .background(isDisabled ? CashRunwayTheme.textMuted : CashRunwayTheme.accent, in: Capsule())
    }
    .disabled(isDisabled)
    .padding(.horizontal, 20)
    .padding(.vertical, 12)
    .background(.ultraThinMaterial)
}

private func flowPill(_ title: String, isActive: Bool) -> some View {
    Text(title)
        .font(.system(size: 11, weight: .bold))
        .foregroundStyle(isActive ? CashRunwayTheme.accentDark : CashRunwayTheme.textMuted)
        .lineLimit(1)
        .minimumScaleFactor(0.75)
        .padding(.horizontal, 9)
        .padding(.vertical, 6)
        .background(isActive ? CashRunwayTheme.accentMuted : CashRunwayTheme.pill, in: Capsule())
}

private func connectionHeader(title: String, subtitle: String, icon: String) -> some View {
    HStack(spacing: 12) {
        Image(systemName: icon)
            .font(.system(size: 22, weight: .semibold))
            .foregroundStyle(CashRunwayTheme.accentDark)
            .frame(width: 48, height: 48)
            .background(CashRunwayTheme.accentMuted, in: Circle())
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(CashRunwayTheme.headingFont)
                .foregroundStyle(CashRunwayTheme.textPrimary)
            Text(subtitle)
                .font(CashRunwayTheme.bodyFont)
                .foregroundStyle(CashRunwayTheme.textSecondary)
        }
    }
    .padding(.vertical, 6)
}

private enum MonobankWizardStep {
    case intro
    case token
    case accounts
    case confirmation
}

private struct MonobankConnectionView: View {
    @Bindable var model: CashRunwayAppModel

    var body: some View {
        let status = model.monobankConnectionStatus()
        if let integration = status.integration, integration.status != .disabled {
            MonobankConnectionStatusView(model: model, status: status)
        } else {
            MonobankConnectionWizardView(model: model)
        }
    }
}

private struct MonobankConnectionWizardView: View {
    @Environment(\.dismiss) private var dismiss
    @Bindable var model: CashRunwayAppModel
    @State private var step: MonobankWizardStep = .intro
    @State private var token = ""
    @State private var clientInfo: MonobankClientInfo?
    @State private var enabledAccountIDs: Set<String> = []
    @State private var selectedWalletIDs: [String: UUID] = [:]
    @State private var validationError: String?
    @State private var connectionError: String?
    @State private var isValidating = false
    @State private var isConnecting = false
    @State private var syncStartAt = Date()
    @State private var completedStatus: BankConnectionStatusSnapshot?

    var body: some View {
        if let completedStatus {
            MonobankConnectionStatusView(model: model, status: completedStatus)
        } else {
            NavigationStack {
            Group {
                switch step {
                case .intro:
                    MonobankTokenIntroView {
                        step = .token
                    }
                case .token:
                    MonobankTokenStepView(
                        token: $token,
                        isValidating: isValidating,
                        error: validationError,
                        onValidate: validateToken
                    )
                case .accounts:
                    MonobankAccountSelectionView(
                        model: model,
                        accounts: clientInfo?.accounts ?? [],
                        enabledAccountIDs: $enabledAccountIDs,
                        selectedWalletIDs: $selectedWalletIDs,
                        onContinue: {
                            syncStartAt = Date()
                            step = .confirmation
                        }
                    )
                case .confirmation:
                    MonobankStartConfirmationView(
                        syncStartAt: syncStartAt,
                        isConnecting: isConnecting,
                        error: connectionError,
                        onStart: startSyncing
                    )
                }
            }
            .navigationTitle("Monobank")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
        }
    }

    private func validateToken() {
        guard !isValidating else { return }
        validationError = nil
        isValidating = true
        Task { @MainActor in
            do {
                let info = try await model.validateMonobankToken(token)
                clientInfo = info
                let uahIDs = Set(info.accounts.filter { $0.currencyCode == 980 }.map(\.id))
                enabledAccountIDs = uahIDs
                let fallbackWalletID = model.wallets.first?.id
                selectedWalletIDs = Dictionary(uniqueKeysWithValues: info.accounts.compactMap { account in
                    guard account.currencyCode == 980, let fallbackWalletID else { return nil }
                    return (account.id, fallbackWalletID)
                })
                step = .accounts
            } catch {
                validationError = error.localizedDescription
            }
            isValidating = false
        }
    }

    private func startSyncing() {
        guard !isConnecting else { return }
        connectionError = nil
        isConnecting = true
        syncStartAt = Date()
        Task { @MainActor in
            do {
                let selections = (clientInfo?.accounts ?? []).map { account in
                    MonobankAccountConnectionSelection(
                        account: account,
                        walletID: selectedWalletIDs[account.id] ?? model.wallets.first?.id ?? UUID(),
                        isEnabled: enabledAccountIDs.contains(account.id)
                    )
                }
                _ = try await model.connectMonobank(token: token, selections: selections, syncStartAt: syncStartAt)
                completedStatus = model.monobankConnectionStatus()
            } catch {
                connectionError = error.localizedDescription
            }
            isConnecting = false
        }
    }
}

private struct MonobankTokenIntroView: View {
    let onContinue: () -> Void

    var body: some View {
        Form {
            Section {
                connectionHeader(title: "Connect Monobank", subtitle: "Only new selected UAH card expenses will sync.", icon: "creditcard.fill")
            }
            Section {
                Text("Cash Runway will import only new Monobank card expenses after connection.")
                Text("Old bank history will not be imported.")
                Text("Existing Cash Runway transactions will not be changed.")
                Text("Income will not be imported.")
                Text("Your Monobank token stays on this iPhone.")
            } header: {
                Text("Connect Monobank")
            }

            Section {
                Button("Continue", action: onContinue)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .accessibilityIdentifier(CashRunwayAccessibilityID.monobankIntroContinueButton)
            }
        }
        .scrollContentBackground(.hidden)
        .background(CashRunwayTheme.background)
    }
}

private struct MonobankTokenStepView: View {
    @Binding var token: String
    let isValidating: Bool
    let error: String?
    let onValidate: () -> Void

    var body: some View {
        Form {
            Section {
                connectionHeader(title: "Personal Token", subtitle: "Validate the token before choosing cards.", icon: "key.fill")
            }
            Section {
                // XCUITest types into SecureField extremely slowly; use TextField in UI-test mode.
                if ProcessInfo.processInfo.environment["CASH_RUNWAY_UI_TEST_MODE"] == "1" {
                    TextField("Personal API token", text: $token)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .accessibilityIdentifier(CashRunwayAccessibilityID.monobankTokenField)
                } else {
                    SecureField("Personal API token", text: $token)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .accessibilityIdentifier(CashRunwayAccessibilityID.monobankTokenField)
                }
                #if canImport(UIKit)
                Button("Paste from Clipboard") {
                    token = UIPasteboard.general.string ?? token
                }
                .accessibilityIdentifier(CashRunwayAccessibilityID.monobankPasteTokenButton)
                #endif
                Button(isValidating ? "Validating..." : "Validate Token", action: onValidate)
                    .disabled(token.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isValidating)
                    .accessibilityIdentifier(CashRunwayAccessibilityID.monobankValidateButton)
            }

            if let error {
                Section("Validation Error") {
                    Text(error)
                        .foregroundStyle(CashRunwayTheme.negative)
                        .accessibilityIdentifier(CashRunwayAccessibilityID.monobankValidationError)
                }
            }
        }
        .scrollContentBackground(.hidden)
        .background(CashRunwayTheme.background)
    }
}

private struct MonobankAccountSelectionView: View {
    @Bindable var model: CashRunwayAppModel
    let accounts: [MonobankAccount]
    @Binding var enabledAccountIDs: Set<String>
    @Binding var selectedWalletIDs: [String: UUID]
    let onContinue: () -> Void

    var body: some View {
        Form {
            Section {
                connectionHeader(title: "Choose Cards", subtitle: "Map each enabled UAH account to a wallet.", icon: "rectangle.stack.fill")
            }
            Section("Cards") {
                ForEach(accounts, id: \.id) { account in
                    if account.currencyCode == 980 {
                        VStack(alignment: .leading, spacing: 8) {
                            Toggle(accountTitle(account), isOn: Binding(
                                get: { enabledAccountIDs.contains(account.id) },
                                set: { isEnabled in
                                    if isEnabled {
                                        enabledAccountIDs.insert(account.id)
                                    } else {
                                        enabledAccountIDs.remove(account.id)
                                    }
                                }
                            ))
                            .accessibilityIdentifier(CashRunwayAccessibilityID.monobankAccountToggle(account.id))
                            Picker("Map to wallet", selection: Binding(
                                get: { selectedWalletIDs[account.id] ?? model.wallets.first?.id ?? UUID() },
                                set: { selectedWalletIDs[account.id] = $0 }
                            )) {
                                ForEach(model.wallets) { wallet in
                                    Text(wallet.name).tag(wallet.id)
                                }
                            }
                            Button("Create Monobank wallet") {
                                createWallet(for: account)
                            }
                        }
                        .accessibilityIdentifier(CashRunwayAccessibilityID.monobankAccountRow(account.id))
                    } else {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(accountTitle(account))
                            Text("Not supported in MVP")
                                .font(.footnote)
                                .foregroundStyle(CashRunwayTheme.textSecondary)
                        }
                        .accessibilityIdentifier(CashRunwayAccessibilityID.monobankAccountRow(account.id))
                    }
                }
            }

            Section {
                Button("Continue", action: onContinue)
                    .disabled(!hasEnabledMappedAccount)
                    .accessibilityIdentifier(CashRunwayAccessibilityID.monobankAccountsContinueButton)
            } footer: {
                Text("Only selected UAH card accounts will sync.")
            }
        }
        .scrollContentBackground(.hidden)
        .background(CashRunwayTheme.background)
    }

    private var hasEnabledMappedAccount: Bool {
        accounts.contains { account in
            account.currencyCode == 980 && enabledAccountIDs.contains(account.id) && selectedWalletIDs[account.id] != nil
        }
    }

    private func accountTitle(_ account: MonobankAccount) -> String {
        let type = (account.type?.isEmpty == false ? account.type! : "Card").capitalized
        let suffix = account.maskedPan?.first.map { " ****\(String($0.suffix(4)))" } ?? ""
        let currency = account.currencyCode == 980 ? "UAH" : String(account.currencyCode)
        return "\(type) card\(suffix) · \(currency)"
    }

    private func createWallet(for account: MonobankAccount) {
        let suffix = account.maskedPan?.first.map { " ****\(String($0.suffix(4)))" } ?? ""
        let type = (account.type?.isEmpty == false ? account.type! : "Card").capitalized
        let wallet = Wallet(
            id: UUID(),
            name: "Monobank \(type)\(suffix)",
            kind: .card,
            colorHex: "#1CC389",
            iconName: "creditcard.fill",
            startingBalanceMinor: 0,
            currentBalanceMinor: 0,
            isArchived: false,
            sortOrder: model.wallets.count,
            createdAt: .now,
            updatedAt: .now
        )
        selectedWalletIDs[account.id] = wallet.id
        model.saveWallet(wallet)
    }
}

private struct MonobankStartConfirmationView: View {
    let syncStartAt: Date
    let isConnecting: Bool
    let error: String?
    let onStart: () -> Void

    var body: some View {
        Form {
            Section {
                connectionHeader(title: "Start Sync", subtitle: "Confirm exactly what Cash Runway will import.", icon: "arrow.triangle.2.circlepath")
            }
            Section("Sync starts from now") {
                summaryRow("Start time", value: Self.dateFormatter.string(from: syncStartAt))
            }

            Section("Cash Runway will import") {
                Text("New Monobank expenses after \(Self.dateFormatter.string(from: syncStartAt))")
                Text("Only selected UAH card accounts")
                Text("Only outgoing expenses")
            }

            Section("Cash Runway will not") {
                Text("Import old bank history")
                Text("Import income")
                Text("Modify existing manual, CSV, or recurring transactions")
            }

            if let error {
                Section("Connection Error") {
                    Text(error)
                        .foregroundStyle(CashRunwayTheme.negative)
                        .accessibilityIdentifier(CashRunwayAccessibilityID.monobankConnectionError)
                }
            }

            Section {
                Button(isConnecting ? "Starting..." : "Start syncing new expenses", action: onStart)
                    .disabled(isConnecting)
                    .accessibilityIdentifier(CashRunwayAccessibilityID.monobankStartSyncButton)
            }
        }
        .scrollContentBackground(.hidden)
        .background(CashRunwayTheme.background)
    }

    private func summaryRow(_ title: String, value: String) -> some View {
        HStack {
            Text(title)
            Spacer()
            Text(value)
                .foregroundStyle(CashRunwayTheme.textSecondary)
        }
    }

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .medium
        return formatter
    }()
}

private struct MonobankConnectionStatusView: View {
    @Environment(\.dismiss) private var dismiss
    @Bindable var model: CashRunwayAppModel
    let status: BankConnectionStatusSnapshot
    @State private var isSyncing = false
    @State private var isAccountManagementPresented = false
    @State private var isDisconnectConfirmationPresented = false

    var body: some View {
        let currentStatus = model.monobankConnectionStatus()
        NavigationStack {
            Form {
                Section {
                    summaryRow("Connected accounts", value: "\(currentStatus.enabledAccountCount)")
                    summaryRow("Sync starts from", value: dateText(currentStatus.syncStartAt))
                    summaryRow("Last successful sync", value: dateText(currentStatus.lastSuccessfulSyncAt))
                    summaryRow("Imported expenses", value: "\(currentStatus.importedExpenseCount)", valueIdentifier: CashRunwayAccessibilityID.monobankImportedExpensesValue)
                    if let message = model.bankSyncMessage ?? currentStatus.lastSyncError {
                        summaryRow("Last result", value: message, valueIdentifier: CashRunwayAccessibilityID.monobankLastResultValue)
                    } else {
                        summaryRow("Last result", value: "success", valueIdentifier: CashRunwayAccessibilityID.monobankLastResultValue)
                    }
                } header: {
                    Text("Monobank connected")
                        .accessibilityIdentifier(CashRunwayAccessibilityID.monobankStatusScreen)
                }

                Section("Diagnostics") {
                    summaryRow("Provider", value: "Monobank")
                    summaryRow("Enabled accounts", value: "\(currentStatus.enabledAccountCount)")
                    summaryRow("Sync start", value: dateText(currentStatus.syncStartAt))
                    summaryRow("Last sync", value: dateText(currentStatus.lastSuccessfulSyncAt))
                    summaryRow("Imported expenses", value: "\(currentStatus.importedExpenseCount)")
                }

                Section {
                    Button(isSyncing ? "Syncing..." : "Sync now") {
                        syncNow()
                    }
                    .disabled(isSyncing)
                    .accessibilityIdentifier(CashRunwayAccessibilityID.monobankSyncNowButton)
                    Button("Manage accounts") {
                        isAccountManagementPresented = true
                    }
                    .accessibilityIdentifier(CashRunwayAccessibilityID.monobankManageAccountsButton)
                    Button("Disconnect", role: .destructive) {
                        isDisconnectConfirmationPresented = true
                    }
                    .accessibilityIdentifier(CashRunwayAccessibilityID.monobankDisconnectButton)
                }
            }
            .navigationTitle("Monobank")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
            .alert("Disconnect Monobank?", isPresented: $isDisconnectConfirmationPresented) {
                Button("Cancel", role: .cancel) {}
                Button("Disconnect", role: .destructive) {
                    if let integration = status.integration {
                        model.disconnectBankIntegration(integration.id)
                    }
                }
            } message: {
                Text("Imported transactions stay in Cash Runway. Only future Monobank sync is disabled on this iPhone.")
            }
            .sheet(isPresented: $isAccountManagementPresented) {
                if let integration = currentStatus.integration {
                    MonobankAccountManagementView(model: model, integrationID: integration.id)
                }
            }
        }
    }

    private func syncNow() {
        guard !isSyncing else { return }
        isSyncing = true
        Task { @MainActor in
            await model.syncMonobankNow()
            isSyncing = false
        }
    }

    private func summaryRow(_ title: String, value: String, valueIdentifier: String? = nil) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
                .foregroundStyle(CashRunwayTheme.textSecondary)
            Spacer(minLength: 16)
            if let valueIdentifier {
                Text(value)
                    .multilineTextAlignment(.trailing)
                    .foregroundStyle(CashRunwayTheme.textPrimary)
                    .accessibilityIdentifier(valueIdentifier)
            } else {
                Text(value)
                    .multilineTextAlignment(.trailing)
                    .foregroundStyle(CashRunwayTheme.textPrimary)
            }
        }
    }

    private func dateText(_ date: Date?) -> String {
        guard let date else { return "Never" }
        return Self.dateFormatter.string(from: date)
    }

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .medium
        return formatter
    }()
}

private struct MonobankAccountManagementView: View {
    @Environment(\.dismiss) private var dismiss
    @Bindable var model: CashRunwayAppModel
    let integrationID: UUID

    var body: some View {
        NavigationStack {
            Form {
                Section("Connected accounts") {
                    ForEach(model.monobankConnectedAccounts(integrationID: integrationID)) { account in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(account.displayName)
                            Text(accountSummary(account))
                                .font(.footnote)
                                .foregroundStyle(CashRunwayTheme.textSecondary)
                        }
                    }
                }
            }
            .navigationTitle("Manage accounts")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    private func accountSummary(_ account: BankAccount) -> String {
        let walletName = model.wallets.first(where: { $0.id == account.walletID })?.name ?? "Unknown wallet"
        let state = account.isEnabled ? "Enabled" : "Disabled"
        return "\(state) · \(walletName)"
    }
}

// LEGACY_DISABLED_APP_LOCK:
// App Lock is disabled for MVP. Do not wire into runtime without a new product decision.
// private struct LockConfigurationView: View {
//     @Environment(\.dismiss) private var dismiss
//     @Bindable var model: CashRunwayAppModel
//     @State private var pin = ""
//     @State private var biometrics = true
//
//     var body: some View {
//         NavigationStack {
//             Form {
//                 SecureField("PIN", text: $pin)
//                     .keyboardType(.numberPad)
//                 Toggle("Enable biometrics", isOn: $biometrics)
//             }
//             .navigationTitle("App Lock")
//             .toolbar {
//                 ToolbarItem(placement: .topBarLeading) {
//                     Button("Cancel") { dismiss() }
//                 }
//                 ToolbarItem(placement: .topBarTrailing) {
//                     Button("Save") {
//                         model.enableLock(pin: pin, biometrics: biometrics)
//                         dismiss()
//                     }
//                     .disabled(pin.isEmpty)
//                 }
//             }
//         }
//     }
// }

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
                Section {
                    importFlowHeader
                }
                .listRowBackground(CashRunwayTheme.surface)

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
            .scrollContentBackground(.hidden)
            .background(CashRunwayTheme.background)
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

    private var importFlowHeader: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                Image(systemName: "tray.and.arrow.down.fill")
                    .font(.system(size: 24, weight: .semibold))
                    .foregroundStyle(CashRunwayTheme.dataTint)
                    .frame(width: 48, height: 48)
                    .background(CashRunwayTheme.dataTint.opacity(0.14), in: Circle())
                VStack(alignment: .leading, spacing: 4) {
                    Text("Import Review")
                        .font(CashRunwayTheme.headingFont)
                        .foregroundStyle(CashRunwayTheme.textPrimary)
                    Text("Confirm mapping, preview rows, then import.")
                        .font(CashRunwayTheme.bodyFont)
                        .foregroundStyle(CashRunwayTheme.textSecondary)
                }
            }
            HStack(spacing: 8) {
                flowPill("Source", isActive: true)
                flowPill("Mapping", isActive: hasRequiredMapping)
                flowPill("Preview", isActive: !reviewRows.isEmpty)
                flowPill("Result", isActive: importResult != nil)
            }
        }
        .padding(.vertical, 6)
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
            if result.insertedTransactions == 0, result.duplicateRows > 0 {
                SwiftUI.Label("No new transactions. This file appears to have already been imported.", systemImage: "checkmark.circle")
                    .foregroundStyle(CashRunwayTheme.textSecondary)
            } else if result.insertedTransactions == 0, result.invalidRows > 0 {
                SwiftUI.Label("No transactions were imported. Review the row errors below.", systemImage: "exclamationmark.triangle")
                    .foregroundStyle(CashRunwayTheme.negative)
            } else if result.insertedTransactions > 0, result.invalidRows > 0 {
                SwiftUI.Label("Imported valid rows. Some rows were skipped because they could not be parsed.", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(CashRunwayTheme.positive)
            } else {
                SwiftUI.Label("Imported \(result.insertedTransactions) transactions", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(CashRunwayTheme.positive)
            }

            if result.duplicateRows > 0 {
                Text("Skipped duplicates: \(result.duplicateRows)")
                    .foregroundStyle(CashRunwayTheme.textSecondary)
            }
            if result.invalidRows > 0 {
                Text("Failed rows: \(result.invalidRows)")
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
                importResult = try await model.importCSV(data: data, fileName: fileName, mapping: mapping)
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
