@testable import CashRunwayCore
@testable import CashRunwayUIVM
import Foundation
import Testing

@MainActor
@Suite("BackupViewModelRegression")
struct BackupViewModelRegressionTests {
    @Test("prepareImport clears stale restore state")
    func prepareImportClearsRestoreState() async throws {
        let service = FakeBackupService()
        service.validationSummary = BackupValidationSummary(
            createdAt: Date(timeIntervalSince1970: 1_000_000),
            walletCount: 1,
            categoryCount: 1,
            labelCount: 1,
            transactionCount: 1,
            recurringTemplateCount: 1
        )
        let viewModel = BackupViewModel(backupService: service)
        viewModel.restoreMessage = "stale success"
        viewModel.restoreError = "stale error"
        viewModel.isRestoreConfirmationPresented = true
        viewModel.isRestoring = true

        let url = try temporaryJSONURL(contents: "{}")
        defer {
            try? FileManager.default.removeItem(at: url)
        }

        viewModel.prepareImport(from: url)
        try await waitFor { viewModel.importSummary != nil }

        #expect(viewModel.restoreMessage == nil)
        #expect(viewModel.restoreError == nil)
        #expect(!viewModel.isRestoreConfirmationPresented)
        #expect(!viewModel.isRestoring)
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
