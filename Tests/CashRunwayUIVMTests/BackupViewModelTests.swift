@testable import CashRunwayCore
@testable import CashRunwayUIVM
import Foundation
import Testing

@Suite("BackupViewModel")
@MainActor
struct BackupViewModelTests {
    @Test("prepareImport updates summary on success")
    func prepareImportSuccess() async throws {
        let service = FakeBackupService()
        service.validationSummary = BackupValidationSummary(
            createdAt: Date(timeIntervalSince1970: 1_000_000),
            walletCount: 3,
            categoryCount: 5,
            labelCount: 2,
            transactionCount: 42,
            recurringTemplateCount: 1
        )
        let viewModel = BackupViewModel(backupService: service)

        let url = try temporaryJSONURL(contents: "{}")
        viewModel.prepareImport(from: url)
        try await waitFor { viewModel.importSummary != nil }

        #expect(viewModel.importFileName.hasSuffix(".json"))
        #expect(viewModel.importSummary?.walletCount == 3)
        #expect(viewModel.preparationError == nil)
    }

    @Test("prepareImport surfaces error on failure")
    func prepareImportFailure() async throws {
        let service = FakeBackupService()
        service.validateShouldFail = true
        let viewModel = BackupViewModel(backupService: service)

        let url = try temporaryJSONURL(contents: "{}")
        viewModel.prepareImport(from: url)
        try await waitFor { viewModel.preparationError != nil }

        #expect(viewModel.importSummary == nil)
    }

    @Test("startRestore sets restore message and calls onSuccess")
    func startRestoreSuccess() async throws {
        let service = FakeBackupService()
        let viewModel = BackupViewModel(backupService: service)
        viewModel.importData = Data()

        var successCalled = false
        viewModel.onSuccess = { successCalled = true }

        await viewModel.startRestore()

        #expect(viewModel.restoreMessage == "Backup restored successfully.")
        #expect(viewModel.restoreError == nil)
        #expect(viewModel.isRestoring == false)
        #expect(successCalled)
    }

    @Test("startRestore sets restore error and calls onFailure")
    func startRestoreFailure() async throws {
        let service = FakeBackupService()
        service.restoreShouldFail = true
        let viewModel = BackupViewModel(backupService: service)
        viewModel.importData = Data()

        var failureCalled = false
        var failureMessage: String?
        viewModel.onFailure = { message in
            failureCalled = true
            failureMessage = message
        }
        var willRestoreCalled = false
        viewModel.onWillRestore = { willRestoreCalled = true }

        await viewModel.startRestore()

        #expect(viewModel.restoreMessage == nil)
        #expect(viewModel.restoreError != nil)
        #expect(viewModel.isRestoring == false)
        #expect(failureCalled)
        #expect(failureMessage == "Backup could not be restored. Your current data was not changed.")
        #expect(willRestoreCalled)
    }

    private func temporaryJSONURL(contents: String) throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).json")
        try contents.write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    private func waitFor(
        timeout: Duration = .milliseconds(500),
        _ condition: @escaping () -> Bool
    ) async throws {
        let deadline = ContinuousClock().now + timeout
        while !condition() {
            if ContinuousClock().now >= deadline {
                throw CancellationError()
            }
            await Task.yield()
        }
    }
}
