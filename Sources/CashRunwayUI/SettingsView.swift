import Foundation
import SwiftUI
import UniformTypeIdentifiers
#if canImport(UIKit)
import UIKit
#endif
import CashRunwayCore

struct SettingsView: View {
    @Bindable var model: CashRunwayAppModel
    @State private var isCategoryManagementPresented = false
    @State private var isLabelsPresented = false
    @State private var isTemplatesPresented = false
    @State private var isWalletsPresented = false
    @State private var monobankCoordinator: MonobankCoordinator? = nil
    @State private var csvImportCoordinator: CSVImportCoordinator? = nil
    @State private var isCSVImporterPresented = false
    @State private var isCSVExporterPresented = false
    @State private var exportFileURL: URL?
    @State private var isExporting = false
    @State private var backupCoordinator: BackupCoordinator? = nil
    @State private var isBackupImporterPresented = false
    @State private var isBackupExportWarningPresented = false
    @State private var isBackupExporterPresented = false
    @State private var backupExportFileURL: URL?
    @State private var isBackupExporting = false
    @State private var isFeedbackReportPresented = false
    @State private var isDiagnosticsPresented = false
    @State private var isLanguageSettingsPresented = false
    @AppStorage(AppLanguagePreference.storageKey) private var languagePreferenceRaw = AppLanguagePreference.system.rawValue

    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 24) {
                    ScreenTitle(title: "More")

                    VStack(alignment: .leading, spacing: 10) {
                        Text("Support")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(CashRunwayTheme.textMuted)
                            .textCase(.uppercase)
                            .padding(.horizontal, 4)

                        VStack(spacing: 0) {
                            moreRow(
                                icon: "exclamationmark.bubble.fill",
                                tint: "#E5862F",
                                title: "Feedback",
                                subtitle: L10n.string("Report a bug or suggest a feature")
                            ) {
                                isFeedbackReportPresented = true
                            }
                            .accessibilityIdentifier(CashRunwayAccessibilityID.settingsFeedbackReportRow)
                        }
                        .background(CashRunwayTheme.surface, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 28, style: .continuous).stroke(CashRunwayTheme.line, lineWidth: 1))
                    }

                    VStack(alignment: .leading, spacing: 10) {
                        Text("Settings")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(CashRunwayTheme.textMuted)
                            .textCase(.uppercase)
                            .padding(.horizontal, 4)

                        VStack(spacing: 0) {
                            moreRow(icon: "square.grid.2x2", tint: "#64D1D5", title: "Categories", subtitle: L10n.string("Manage visibility, order, and merges")) {
                                isCategoryManagementPresented = true
                            }
                            .accessibilityIdentifier(CashRunwayAccessibilityID.settingsCategoriesRow)
                            rowDivider
                            moreRow(icon: "tag.fill", tint: "#F7A72A", title: "Labels", subtitle: L10n.labelCount(model.labels.count)) {
                                isLabelsPresented = true
                            }
                            .accessibilityIdentifier(CashRunwayAccessibilityID.settingsLabelsRow)
                            rowDivider
                            moreRow(icon: "repeat", tint: "#1CC389", title: "Scheduled Transactions", subtitle: L10n.templateCount(model.templates.count)) {
                                isTemplatesPresented = true
                            }
                            .accessibilityIdentifier(CashRunwayAccessibilityID.settingsScheduledTransactionsRow)
                            rowDivider
                            staticRow(icon: "banknote.fill", tint: "#4A80C1", title: "Main Currency", value: "UAH")
                            .accessibilityIdentifier(CashRunwayAccessibilityID.settingsMainCurrencyRow)
                            rowDivider
                            moreRow(icon: "globe", tint: "#2AAAD2", title: "Language", subtitle: languagePreference.displayName) {
                                isLanguageSettingsPresented = true
                            }
                            .accessibilityIdentifier(CashRunwayAccessibilityID.settingsLanguageRow)
                            rowDivider
                            moreRow(icon: "wallet.pass.fill", tint: "#60788A", title: "Manual Wallets", subtitle: L10n.walletCount(model.wallets.count)) {
                                isWalletsPresented = true
                            }
                            .accessibilityIdentifier(CashRunwayAccessibilityID.settingsWalletsRow)
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
                            moreRow(icon: "tray.and.arrow.down.fill", tint: "#5FD4BF", title: "Import Bank Statement", subtitle: L10n.string("Import CSV or bank XLSX exports")) {
                                if model.hasBootstrapped && model.wallets.isEmpty {
                                    model.errorMessage = L10n.string("Create at least one wallet before importing.")
                                } else {
                                    isCSVImporterPresented = true
                                }
                            }
                            .accessibilityIdentifier(CashRunwayAccessibilityID.settingsImportCSVRow)
                            rowDivider
                            moreRow(icon: "square.and.arrow.up.fill", tint: "#E5862F", title: "Export CSV", subtitle: isExporting ? L10n.string("Exporting…") : L10n.string("Share the current filtered export")) {
                                guard !isExporting else { return }
                                isExporting = true
                                let query = model.transactionQuery
                                Task {
                                    do {
                                        let csv = try await model.exportCSV(query: query)
                                        let url = FileManager.default.temporaryDirectory.appendingPathComponent("cash-runway-export.csv")
                                        try csv.write(to: url, atomically: true, encoding: .utf8)
                                        await MainActor.run {
                                            exportFileURL = url
                                            isCSVExporterPresented = true
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
                            .accessibilityIdentifier(CashRunwayAccessibilityID.settingsExportCSVRow)
                            rowDivider
                            moreRow(icon: "externaldrive.fill", tint: "#4A80C1", title: "Import Full Backup", subtitle: L10n.string("Replace data from JSON")) {
                                isBackupImporterPresented = true
                            }
                            .accessibilityIdentifier(CashRunwayAccessibilityID.settingsImportBackupRow)
                            rowDivider
                            moreRow(icon: "externaldrive.badge.plus", tint: "#7A6FF0", title: "Export Full Backup", subtitle: isBackupExporting ? L10n.string("Exporting…") : L10n.string("Share unencrypted backup JSON")) {
                                guard !isBackupExporting else { return }
                                isBackupExportWarningPresented = true
                            }
                            .accessibilityIdentifier(CashRunwayAccessibilityID.settingsExportBackupRow)
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
                                monobankCoordinator = MonobankCoordinator(model: model)
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
                            moreRow(icon: "wrench.and.screwdriver.fill", tint: "#FF5E57", title: "Diagnostics", subtitle: L10n.string("Counts and local state")) {
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
            .sheet(item: $monobankCoordinator) { coordinator in
                MonobankWizardView(coordinator: coordinator)
            }
            .sheet(item: $csvImportCoordinator) { coordinator in
                CSVImportView(coordinator: coordinator)
            }
            .sheet(isPresented: $isDiagnosticsPresented) {
                DiagnosticsView(model: model)
            }
            .sheet(isPresented: $isLanguageSettingsPresented) {
                LanguageSettingsView(selection: $languagePreferenceRaw)
            }
            .sheet(isPresented: $isCSVExporterPresented) {
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
            .sheet(isPresented: $isCSVImporterPresented) {
                #if canImport(UIKit)
                DocumentPicker(allowedContentTypes: [.commaSeparatedText, .plainText, UTType(filenameExtension: "xlsx") ?? .spreadsheet]) { result in
                    handleCSVImporterResult(result)
                }
                #else
                Text("Bank statement import is unavailable on this platform.")
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
            .sheet(item: $backupCoordinator) { coordinator in
                BackupView(coordinator: coordinator)
            }
            .sheet(isPresented: $isFeedbackReportPresented) {
                FeedbackReportView(service: ConfiguredFeedbackReportService())
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

    private func handleCSVImporterResult(_ result: Result<URL, any Error>) {
        isCSVImporterPresented = false
        switch result {
        case let .success(url):
            let coordinator = CSVImportCoordinator(model: model)
            csvImportCoordinator = coordinator
            coordinator.prepareImport(from: url)
        case let .failure(error):
            if let pickerError = error as? DocumentPickerError, pickerError == .cancelled {
                return
            }
            model.errorMessage = error.localizedDescription
        }
    }

    private func exportFullBackup() {
        isBackupExporting = true
        Task {
            do {
                let data = try await model.exportFullBackupData()
                let url = FileManager.default.temporaryDirectory.appendingPathComponent("cash-runway-backup-\(backupFileTimestamp()).json")
                try data.write(to: url, options: .atomic)
                await MainActor.run {
                    backupExportFileURL = url
                    isBackupExporterPresented = true
                }
            } catch {
                await MainActor.run {
                    model.errorMessage = error.localizedDescription
                }
            }
            await MainActor.run {
                isBackupExporting = false
            }
        }
    }

    private func handleBackupImporterResult(_ result: Result<URL, any Error>) {
        isBackupImporterPresented = false
        switch result {
        case let .success(url):
            let coordinator = BackupCoordinator(model: model)
            backupCoordinator = coordinator
            coordinator.prepareImport(from: url)
        case let .failure(error):
            if let pickerError = error as? DocumentPickerError, pickerError == .cancelled {
                return
            }
            model.errorMessage = error.localizedDescription
        }
    }

    private func backupFileTimestamp() -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd-HHmmss"
        return formatter.string(from: Date())
    }

    private var rowDivider: some View {
        Divider().overlay(CashRunwayTheme.line).padding(.leading, 72)
    }

    private var monobankSubtitle: String {
        let status = model.monobankConnectionStatus()
        guard let integration = status.integration, integration.status != .disabled else {
            return L10n.string("Connect cards and import new expenses automatically")
        }
        if integration.status == .tokenInvalid || integration.status == .syncFailed || status.lastSyncError != nil {
            return L10n.string("Sync failed · Tap to fix")
        }
        if let lastSync = status.lastSuccessfulSyncAt {
            return L10n.string("%@ connected · Last sync %@", L10n.cardCount(status.enabledAccountCount), relativeFormatter.localizedString(for: lastSync, relativeTo: Date()))
        }
        return L10n.string("%@ connected · Waiting for first sync", L10n.cardCount(status.enabledAccountCount))
    }

    private var relativeFormatter: RelativeDateTimeFormatter {
        let formatter = Self._cachedFormatter
        formatter.locale = L10n.locale
        formatter.unitsStyle = .short
        return formatter
    }

    private static let _cachedFormatter: RelativeDateTimeFormatter = {
        RelativeDateTimeFormatter()
    }()

    private var languagePreference: AppLanguagePreference {
        AppLanguagePreference.value(for: languagePreferenceRaw)
    }

    private func moreRow(icon: String, tint: String, title: LocalizedStringKey, subtitle: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            rowContent(icon: icon, tint: tint, title: title, subtitle: subtitle)
        }
        .buttonStyle(.plain)
    }

    private func staticRow(icon: String, tint: String, title: LocalizedStringKey, value: String) -> some View {
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

    private func rowContent(icon: String, tint: String, title: LocalizedStringKey, subtitle: String) -> some View {
        HStack(spacing: 14) {
            CategoryGlyph(iconName: icon, colorHex: tint, size: 44)
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(CashRunwayTheme.textPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
                Text(subtitle)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(CashRunwayTheme.textSecondary)
                    .lineLimit(2)
            }
            Spacer()
            Image(systemName: "chevron.right")
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(CashRunwayTheme.textMuted)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 16)
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
                EmptyView().accessibilityIdentifier(CashRunwayAccessibilityID.scheduledTransactionsScreen)
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

private struct DiagnosticsView: View {
    @Environment(\.dismiss) private var dismiss
    @Bindable var model: CashRunwayAppModel

    var body: some View {
        NavigationStack {
            List {
                Text(L10n.string("Wallets: %d", model.wallets.count))
                Text(L10n.string("Transactions: %d", model.transactions.count))
                Text(L10n.string("Budgets: %d", model.budgets.count))
                Text(L10n.string("Templates: %d", model.templates.count))
                Text(L10n.string("Labels: %d", model.labels.count))
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

private struct LanguageSettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var selection: String

    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 22) {
                    ScreenTitle(title: "Language")

                    VStack(alignment: .leading, spacing: 8) {
                        Text("Choose how Cash Runway decides which language to use.")
                            .font(.system(size: 15, weight: .medium))
                            .foregroundStyle(CashRunwayTheme.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.horizontal, 4)

                        VStack(spacing: 0) {
                            ForEach(AppLanguagePreference.allCases) { option in
                                Button {
                                    selection = option.rawValue
                                } label: {
                                    HStack(spacing: 14) {
                                        CategoryGlyph(iconName: option.iconName, colorHex: option.tint, size: 44)
                                        VStack(alignment: .leading, spacing: 3) {
                                            Text(option.displayName)
                                                .font(.system(size: 17, weight: .semibold))
                                                .foregroundStyle(CashRunwayTheme.textPrimary)
                                            Text(option.subtitle)
                                                .font(.system(size: 14, weight: .medium))
                                                .foregroundStyle(CashRunwayTheme.textSecondary)
                                                .lineLimit(2)
                                        }
                                        Spacer()
                                        if selection == option.rawValue {
                                            Image(systemName: "checkmark.circle.fill")
                                                .font(.system(size: 20, weight: .semibold))
                                                .foregroundStyle(CashRunwayTheme.accent)
                                        }
                                    }
                                    .padding(.horizontal, 18)
                                    .padding(.vertical, 16)
                                }
                                .buttonStyle(.plain)

                                if option != AppLanguagePreference.allCases.last {
                                    Divider().overlay(CashRunwayTheme.line).padding(.leading, 72)
                                }
                            }
                        }
                        .background(CashRunwayTheme.surface, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 28, style: .continuous).stroke(CashRunwayTheme.line, lineWidth: 1))
                    }
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 16)
                .padding(.bottom, 36)
            }
            .background(CashRunwayTheme.background)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}

private extension AppLanguagePreference {
    var subtitle: String {
        switch self {
        case .system:
            L10n.string("Follow iOS language settings")
        case .english:
            L10n.string("Use English in Cash Runway")
        case .ukrainian:
            L10n.string("Use Ukrainian in Cash Runway")
        }
    }

    var iconName: String {
        switch self {
        case .system: "gearshape.fill"
        case .english: "textformat"
        case .ukrainian: "text.bubble.fill"
        }
    }

    var tint: String {
        switch self {
        case .system: "#60788A"
        case .english: "#2AAAD2"
        case .ukrainian: "#21C596"
        }
    }
}

private extension String {
    func ifEmpty(_ fallback: String) -> String {
        isEmpty ? fallback : self
    }
}
