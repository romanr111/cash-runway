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
                                if model.hasBootstrapped && model.wallets.isEmpty {
                                    model.errorMessage = "Create at least one wallet before importing CSV."
                                } else {
                                    isImporterPresented = true
                                }
                            }
                            rowDivider
                            moreRow(icon: "square.and.arrow.up.fill", tint: "#E5862F", title: "Export CSV", subtitle: isExporting ? "Exporting…" : "Share the current filtered export") {
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
                            moreRow(icon: "externaldrive.fill", tint: "#4A80C1", title: "Import Full Backup", subtitle: "Replace data from JSON") {
                                isBackupImporterPresented = true
                            }
                            rowDivider
                            moreRow(icon: "externaldrive.badge.plus", tint: "#7A6FF0", title: "Export Full Backup", subtitle: isBackupExporting ? "Exporting…" : "Share unencrypted backup JSON") {
                                guard !isBackupExporting else { return }
                                isBackupExportWarningPresented = true
                            }
                        }
                        .background(CashRunwayTheme.surface, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 28, style: .continuous).stroke(CashRunwayTheme.line, lineWidth: 1))
                    }

                    VStack(alignment: .leading, spacing: 10) {
                        Text("Bank Connections")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(CashRunwayTheme.textMuted)
                            .textCase(.uppercase)
                            .padding(.horizontal, 4)

                        VStack(spacing: 0) {
                            moreRow(icon: "creditcard.fill", tint: "#1CC389", title: "Monobank", subtitle: monobankSubtitle) {
                                isMonobankConnectionPresented = true
                            }
                            .accessibilityIdentifier(CashRunwayAccessibilityID.settingsMonobankRow)
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
                    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                        if model.wallets.count > 1 {
                            Button(role: .destructive) {
                                model.deleteWallet(id: wallet.id)
                            } label: {
                                SwiftUI.Label("Delete", systemImage: "trash")
                            }
                        }
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
                    } label: {
                        Image(systemName: "plus")
                    }
                    .disabled(model.wallets.isEmpty)
                }
            }
            .sheet(isPresented: $isEditorPresented) {
                RecurringTemplateEditorView(model: model, template: $templateDraft)
            }
        }
    }
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
