import Foundation

public struct BackupImportFlowState {
    public var isBackupImporterPresented = false
    public var isBackupImportViewPresented = false

    public init() {}

    public mutating func beginImport() {
        isBackupImporterPresented = true
        isBackupImportViewPresented = false
    }

    public mutating func presentBackupView() {
        isBackupImporterPresented = false
        isBackupImportViewPresented = true
    }

    public mutating func reset() {
        isBackupImporterPresented = false
        isBackupImportViewPresented = false
    }
}
