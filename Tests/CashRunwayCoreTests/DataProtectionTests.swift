import Foundation
import GRDB
import Testing
@testable import CashRunwayCore

@Suite(.serialized)
struct DataProtectionTests {
    @Test func databaseFilesHaveCompleteProtection() throws {
        let location = TestSupport.makeLocation()
        let keychain = TestKeychainStore()
        _ = try DatabaseManager(locationProvider: location, keychain: keychain)
        let databaseURL = try location.databaseURL()

        #expect(FileManager.default.fileExists(atPath: databaseURL.path))
        try assertCompleteProtectionIfAvailable(databaseURL)
        try assertCompleteProtectionIfAvailable(URL(fileURLWithPath: databaseURL.path + "-wal"), mayBeMissing: true)
        try assertCompleteProtectionIfAvailable(URL(fileURLWithPath: databaseURL.path + "-shm"), mayBeMissing: true)
    }

    @Test func safetyBackupFileHasCompleteProtection() throws {
        let repository = try TestSupport.makeRepository()
        try repository.seedIfNeeded()
        let service = BackupService(repository: repository)

        let url = try service.writeSafetyBackup()

        #expect(FileManager.default.fileExists(atPath: url.path))
        try assertCompleteProtectionIfAvailable(url)
    }

    @Test func recoveryFilesHaveCompleteProtection() throws {
        let location = TestSupport.makeLocation()
        let databaseURL = try location.databaseURL()
        let keychain = TestKeychainStore()
        let manager = try DatabaseManager(locationProvider: location, keychain: keychain)
        try manager.checkpointWal()

        try DatabaseManager.quarantineDatabases(at: databaseURL)

        let recoveryDirectory = databaseURL.deletingLastPathComponent().appendingPathComponent("Recovery", isDirectory: true)
        let recoveryFiles = try FileManager.default.contentsOfDirectory(at: recoveryDirectory, includingPropertiesForKeys: nil)
        #expect(!recoveryFiles.isEmpty)
        for file in recoveryFiles {
            try assertCompleteProtectionIfAvailable(file)
        }
    }

    @Test func runMaintenanceSkipsWhenProtectedDataUnavailable() throws {
        let repository = try TestSupport.makeRepository()
        try repository.seedIfNeeded()

        ProtectedDataMonitor.shared.setOverride(.unavailable(reason: "test"))
        defer { ProtectedDataMonitor.shared.setOverride(nil) }

        // Should not throw and should not run aggregate rebuilds.
        try repository.runMaintenance()

        let pendingCount = try repository.databaseManager.dbQueue.read { db in
            try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM aggregate_dirty_ranges WHERE status = 'pending'") ?? 0
        }
        #expect(pendingCount == 0)
    }

    @Test func bankSyncSkipsWhenProtectedDataUnavailable() async throws {
        let repository = try TestSupport.makeRepository()
        try repository.seedIfNeeded()
        try TestSupport.seedFixtureWallets(into: repository)
        _ = makeBankSetup(repository: repository)
        let client = StubMonobankClient()
        let service = BankSyncService(repository: repository, client: client)

        ProtectedDataMonitor.shared.setOverride(.unavailable(reason: "test"))
        defer { ProtectedDataMonitor.shared.setOverride(nil) }

        let result = try await service.syncOnDemand()
        #expect(result.importedCount == 0)
        #expect(result.skippedCount == 0)
        #expect(result.syncedAccountCount == 0)
    }

    /// File protection classes are only enforced on iOS. On macOS SwiftPM tests
    /// the attribute is unavailable, so this helper asserts only when UIKit is present.
    private func assertCompleteProtectionIfAvailable(_ url: URL, mayBeMissing: Bool = false) throws {
        let path = url.path
        guard FileManager.default.fileExists(atPath: path) else {
            if mayBeMissing { return }
            Issue.record("Expected file to exist: \(path)")
            return
        }
        #if canImport(UIKit)
        let values = try url.resourceValues(forKeys: [.protectionKey])
        let actual = values.protectionKey
        #expect(actual == .complete, "Expected .complete for \(path), got \(String(describing: actual))")
        #endif
    }

    private func makeBankSetup(repository: CashRunwayRepository) -> (integration: BankIntegration, account: BankAccount) {
        let walletID = (try? repository.wallets().first?.id) ?? UUID()
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let syncStartAt = Date(timeIntervalSince1970: 1_700_000_000)
        let integration = BankIntegration(
            id: UUID(),
            provider: .monobank,
            displayName: "Monobank",
            status: .active,
            syncStartAt: syncStartAt,
            tokenKeychainAccount: "mono-token",
            lastClientInfoSyncAt: nil,
            lastSuccessfulSyncAt: nil,
            lastSyncError: nil,
            createdAt: now,
            updatedAt: now
        )
        let account = BankAccount(
            id: UUID(),
            integrationID: integration.id,
            provider: .monobank,
            providerAccountID: "mono-account-1",
            walletID: walletID,
            displayName: "Black Card",
            accountType: "black",
            currencyCode: 980,
            maskedPAN: nil,
            iban: nil,
            isEnabled: true,
            syncStartAt: syncStartAt,
            lastSuccessfulSyncAt: nil,
            lastStatementItemTime: nil,
            createdAt: now,
            updatedAt: now
        )
        return (integration, account)
    }
}

private final class StubMonobankClient: MonobankClient {
    func clientInfo() async throws -> MonobankClientInfo {
        MonobankClientInfo(name: "Test", accounts: [])
    }

    func statement(accountID: String, from: Date, to: Date) async throws -> [MonobankStatementItem] {
        []
    }
}
