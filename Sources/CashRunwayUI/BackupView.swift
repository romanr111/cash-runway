import CashRunwayCore
import CashRunwayUIVM
import Foundation
import SwiftUI

struct BackupView: View {
    @Environment(\.dismiss) private var dismiss
    @Bindable var viewModel: BackupViewModel

    var body: some View {
        NavigationStack {
            Form {
                EmptyView().accessibilityIdentifier(CashRunwayAccessibilityID.backupImportScreen)
                Section("Source") {
                    summaryRow("File", value: viewModel.importFileName)
                }

                if let preparationError = viewModel.preparationError {
                    Section("Import Error") {
                        Text(preparationError)
                            .foregroundStyle(CashRunwayTheme.negative)
                    }
                } else if let summary = viewModel.importSummary {
                    Section("Preview") {
                        summaryRow("Backup created", value: dateText(summary.createdAt))
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

                    if viewModel.isRestoring {
                        Section("Restoring") {
                            ProgressView("Restoring backup...")
                        }
                    }

                    if let restoreMessage = viewModel.restoreMessage {
                        Section("Result") {
                            Text(restoreMessage)
                                .foregroundStyle(CashRunwayTheme.positive)
                        }
                    } else if let restoreError = viewModel.restoreError {
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
                    Button(viewModel.restoreMessage == nil && viewModel.preparationError == nil ? L10n.string("Cancel") : L10n.string("Done")) { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    if viewModel.importSummary != nil, viewModel.preparationError == nil, viewModel.restoreMessage == nil {
                        Button("Restore", role: .destructive) {
                            viewModel.isRestoreConfirmationPresented = true
                        }
                        .disabled(viewModel.isRestoring)
                    }
                }
            }
            .alert("Replace Current Data?", isPresented: $viewModel.isRestoreConfirmationPresented) {
                Button("Cancel", role: .cancel) {}
                Button("Restore", role: .destructive) {
                    Task { await viewModel.startRestore() }
                }
            } message: {
                Text("Restoring this backup will replace all current Cash Runway data on this device. This cannot be merged automatically.")
            }
        }
    }

    private func summaryRow(_ title: LocalizedStringKey, value: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
                .foregroundStyle(CashRunwayTheme.textSecondary)
            Spacer(minLength: 16)
            Text(value)
                .multilineTextAlignment(.trailing)
                .foregroundStyle(CashRunwayTheme.textPrimary)
        }
    }

    private func dateText(_ date: Date) -> String {
        Self.dateFormatter(locale: L10n.locale).string(from: date)
    }

    private static func dateFormatter(locale: Locale) -> DateFormatter {
        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter
    }
}
