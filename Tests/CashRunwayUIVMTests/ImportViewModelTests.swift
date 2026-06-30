@testable import CashRunwayCore
@testable import CashRunwayUIVM
import Foundation
import Testing

@Suite("ImportViewModel")
@MainActor
struct ImportViewModelTests {
    @Test("prepareImport sets preview and format on success")
    func prepareImportSuccess() async throws {
        let service = FakeCSVService()
        service.previewResult = CSVImportPreview(
            headers: ["date", "amount"],
            sampleRows: [["2024-01-01", "100"]],
            totalRows: 1
        )
        let viewModel = ImportViewModel(
            csvService: service,
            walletsProvider: { [] }
        )

        let url = try temporaryCSVURL(contents: "date,amount\n2024-01-01,100")
        viewModel.prepareImport(from: url)
        try await waitFor { !viewModel.isImportPreparing }

        #expect(viewModel.importFileName.hasSuffix(".csv"))
        #expect(viewModel.importPreview.totalRows == 1)
        #expect(viewModel.importPreparationError == nil)
    }

    @Test("prepareImport surfaces error on failure")
    func prepareImportFailure() async throws {
        let service = FakeCSVService()
        service.previewShouldFail = true
        let viewModel = ImportViewModel(
            csvService: service,
            walletsProvider: { [] }
        )

        let url = try temporaryCSVURL(contents: "date,amount\n2024-01-01,100")
        viewModel.prepareImport(from: url)
        try await waitFor { viewModel.importPreparationError != nil }

        #expect(viewModel.importPreparationError != nil)
    }

    @Test("startImport sets result and calls onSuccess")
    func startImportSuccess() async throws {
        let service = FakeCSVService()
        service.importResult = CSVImportResult(
            job: ImportJob(
                id: UUID(),
                sourceName: "test",
                sourceFormatID: nil,
                fileName: "import.csv",
                status: .committed,
                totalRows: 1,
                validRows: 1,
                invalidRows: 0,
                duplicateRows: 0,
                startedAt: Date(),
                finishedAt: Date(),
                errorSummary: nil
            ),
            insertedTransactions: 1,
            duplicateRows: 0,
            invalidRows: 0,
            affectedMonths: [],
            rowErrors: []
        )
        let viewModel = ImportViewModel(
            csvService: service,
            walletsProvider: { [] }
        )
        viewModel.importData = Data()
        viewModel.importMapping = CSVImportMapping(
            dateColumn: "date",
            amountColumn: "amount",
            debitColumn: nil,
            creditColumn: nil,
            merchantColumn: nil,
            noteColumn: nil,
            categoryColumn: nil,
            labelsColumn: nil,
            walletID: UUID(),
            defaultKind: .expense
        )

        var successCalled = false
        viewModel.onSuccess = { successCalled = true }

        await viewModel.startImport()

        #expect(viewModel.importResult?.insertedTransactions == 1)
        #expect(viewModel.importError == nil)
        #expect(viewModel.isImporting == false)
        #expect(successCalled)
    }

    @Test("startImport surfaces error and calls onFailure")
    func startImportFailure() async throws {
        let service = FakeCSVService()
        service.importShouldFail = true
        let viewModel = ImportViewModel(
            csvService: service,
            walletsProvider: { [] }
        )
        viewModel.importData = Data()

        var failureCalled = false
        viewModel.onFailure = { _ in failureCalled = true }

        await viewModel.startImport()

        #expect(viewModel.importError != nil)
        #expect(failureCalled)
    }

    private func temporaryCSVURL(contents: String) throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).csv")
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
