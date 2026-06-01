import Foundation
import SwiftUI
#if canImport(CashRunwayCore)
import CashRunwayCore
#endif

@MainActor
@Observable
final class BackupCoordinator: Identifiable {
    let id = UUID()
    let model: CashRunwayAppModel

    var backupImportData = Data()
    var backupImportFileName = ""
    var backupImportSummary: BackupValidationSummary?
    var backupImportPreparationError: String?
    var isRestoreConfirmationPresented = false
    var isRestoring = false
    var restoreMessage: String?
    var restoreError: String?

    init(model: CashRunwayAppModel) {
        self.model = model
    }

    func prepareImport(from url: URL) {
        let fileName = url.lastPathComponent.isEmpty ? "backup.json" : url.lastPathComponent
        let service = model.backupService
        backupImportData = Data()
        backupImportFileName = fileName
        backupImportSummary = nil
        backupImportPreparationError = nil

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

    func startRestore() {
        guard !isRestoring else { return }
        isRestoring = true
        restoreError = nil
        Task { @MainActor in
            do {
                _ = try await model.restoreFullBackup(data: backupImportData)
                restoreMessage = "Backup restored successfully."
            } catch {
                restoreError = "Backup could not be restored. Your current data was not changed."
            }
            isRestoring = false
        }
    }
}
