import CashRunwayCore
import Foundation
import Observation

@MainActor
@Observable
public final class BackupViewModel: Identifiable {
    public let id = UUID()

    public var importFileName = ""
    public var importSummary: BackupValidationSummary?
    public var preparationError: String?
    public var isRestoreConfirmationPresented = false
    public var isRestoring = false
    public var restoreMessage: String?
    public var restoreError: String?

    public var onWillRestore: (() -> Void)?
    public var onSuccess: (() async -> Void)?
    public var onFailure: ((String) -> Void)?

    private let backupService: any BackupServicing
    var importData = Data()

    public init(backupService: any BackupServicing) {
        self.backupService = backupService
    }

    public func prepareImport(from url: URL) {
        let fileName = url.lastPathComponent.isEmpty ? "backup.json" : url.lastPathComponent
        importFileName = fileName
        importSummary = nil
        preparationError = nil
        importData = Data()

        Task { @MainActor in
            do {
                let data = try ImportFileReader.readData(from: url)
                let backup = try backupService.decode(data: data)
                let summary = try backupService.validate(backup)
                importData = data
                importSummary = summary
            } catch {
                preparationError = error.localizedDescription
            }
        }
    }

    public func startRestore() async {
        guard !isRestoring else { return }
        isRestoring = true
        restoreError = nil
        restoreMessage = nil
        defer { isRestoring = false }
        onWillRestore?()
        do {
            let backup = try backupService.decode(data: importData)
            _ = try backupService.validate(backup)
            _ = try backupService.restore(backup)
            restoreMessage = "Backup restored successfully."
            await onSuccess?()
        } catch {
            let message = "Backup could not be restored. Your current data was not changed."
            restoreError = message
            onFailure?(message)
        }
    }

    public func exportFullBackupData() async throws -> Data {
        let backup = try backupService.exportFullBackup()
        return try backupService.encode(backup)
    }
}
