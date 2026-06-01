import Foundation
import SwiftUI
#if canImport(CashRunwayCore)
import CashRunwayCore
#endif

struct BackupView: View {
    @Environment(\.dismiss) private var dismiss
    @Bindable var coordinator: BackupCoordinator

    var body: some View {
        NavigationStack {
            Form {
                EmptyView().accessibilityIdentifier(CashRunwayAccessibilityID.backupImportScreen)
                Section("Source") {
                    summaryRow("File", value: coordinator.backupImportFileName)
                }

                if let preparationError = coordinator.backupImportPreparationError {
                    Section("Import Error") {
                        Text(preparationError)
                            .foregroundStyle(CashRunwayTheme.negative)
                    }
                } else if let summary = coordinator.backupImportSummary {
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

                    if coordinator.isRestoring {
                        Section("Restoring") {
                            ProgressView("Restoring backup...")
                        }
                    }

                    if let restoreMessage = coordinator.restoreMessage {
                        Section("Result") {
                            Text(restoreMessage)
                                .foregroundStyle(CashRunwayTheme.positive)
                        }
                    } else if let restoreError = coordinator.restoreError {
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
                    Button(coordinator.restoreMessage == nil && coordinator.backupImportPreparationError == nil ? "Cancel" : "Done") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    if coordinator.backupImportSummary != nil, coordinator.backupImportPreparationError == nil, coordinator.restoreMessage == nil {
                        Button("Restore", role: .destructive) {
                            coordinator.isRestoreConfirmationPresented = true
                        }
                        .disabled(coordinator.isRestoring)
                    }
                }
            }
            .alert("Replace Current Data?", isPresented: $coordinator.isRestoreConfirmationPresented) {
                Button("Cancel", role: .cancel) {}
                Button("Restore", role: .destructive) {
                    coordinator.startRestore()
                }
            } message: {
                Text("Restoring this backup will replace all current Cash Runway data on this device. This cannot be merged automatically.")
            }
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
