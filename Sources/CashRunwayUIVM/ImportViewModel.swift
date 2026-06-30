import CashRunwayCore
import Foundation
import Observation

@MainActor
@Observable
public final class ImportViewModel: Identifiable {
    public let id = UUID()

    public var importData = Data()
    public var importFileName = ""
    public var importFormat: BankStatementFormat = .genericBankCSV
    public var importPreview = CSVImportPreview(headers: [], sampleRows: [], totalRows: 0)
    public var importMapping = CSVImportMapping(
        dateColumn: "",
        amountColumn: nil,
        debitColumn: nil,
        creditColumn: nil,
        merchantColumn: nil,
        noteColumn: nil,
        categoryColumn: nil,
        labelsColumn: nil,
        walletID: UUID(),
        defaultKind: .expense
    )
    public var isImportPreparing = false
    public var importPreparationProgress = 0.0
    public var importPreparationStatus = ""
    public var importPreparationError: String?

    public var importResult: CSVImportResult?
    public var importError: String?
    public var isImporting = false
    public var isAdvancedMappingExpanded = false
    public var importExpensesOnly = false

    public var onSuccess: (() async -> Void)?
    public var onFailure: ((String) -> Void)?

    public var rowFilter: CSVImportRowFilter {
        importExpensesOnly ? .expensesOnly : .allTransactions
    }

    public var wallets: [Wallet] { walletsProvider() }

    private let csvService: any CSVImportServicing
    private let walletsProvider: () -> [Wallet]

    public init(
        csvService: any CSVImportServicing,
        walletsProvider: @escaping () -> [Wallet]
    ) {
        self.csvService = csvService
        self.walletsProvider = walletsProvider
    }

    public func previewPreparedRows(
        data: Data,
        mapping: CSVImportMapping,
        rowFilter: CSVImportRowFilter,
        limit: Int
    ) throws -> [PreparedImportRow] {
        try csvService.previewPreparedRows(
            data: data,
            mapping: mapping,
            rowFilter: rowFilter,
            limit: limit
        )
    }

    public func prepareImport(from url: URL) {
        let fileName = url.lastPathComponent.isEmpty ? "import.csv" : url.lastPathComponent
        importData = Data()
        importFileName = fileName
        importPreview = CSVImportPreview(headers: [], sampleRows: [], totalRows: 0)
        importFormat = .genericBankCSV
        importExpensesOnly = false
        importMapping = defaultMapping(headers: [], format: .genericBankCSV)
        importPreparationError = nil
        importPreparationProgress = 0.12
        importPreparationStatus = "Reading CSV rows..."
        isImportPreparing = true
        importResult = nil
        importError = nil

        let defaultWalletID = walletsProvider().first?.id

        Task {
            do {
                let result = try await Task.detached(priority: .userInitiated) { [csvService, defaultWalletID] in
                    let (csvData, fileKind) = try ImportFileReader.readCSVData(from: url)
                    let preview = try csvService.preview(data: csvData)
                    let format = csvService.detectFormat(headers: preview.headers, fileKind: fileKind)
                    let mapping = csvService.defaultMapping(
                        headers: preview.headers,
                        format: format,
                        walletID: defaultWalletID
                    )
                    return (csvData, preview, format, mapping)
                }.value

                await MainActor.run {
                    importPreparationProgress = 0.55
                    importData = result.0
                    importPreview = result.1
                    importFormat = result.2
                    importMapping = result.3
                    importPreparationProgress = 1.0
                    importPreparationStatus = "Ready to review."
                    isImportPreparing = false
                }
            } catch {
                await MainActor.run {
                    importPreparationError = error.localizedDescription
                    importPreparationProgress = 0.0
                    isImportPreparing = false
                }
            }
        }
    }

    public func startImport() async {
        guard !isImporting else { return }
        importError = nil
        isImporting = true
        defer { isImporting = false }

        await Task.yield()
        do {
            importResult = try csvService.importStatement(
                normalizedData: importData,
                fileName: importFileName,
                format: importFormat,
                mapping: importMapping,
                rowFilter: rowFilter
            )
            await onSuccess?()
        } catch {
            let message = error.localizedDescription
            importError = message
            onFailure?(message)
        }
    }

    public func defaultMapping(headers: [String], format: BankStatementFormat) -> CSVImportMapping {
        csvService.defaultMapping(
            headers: headers,
            format: format,
            walletID: walletsProvider().first?.id
        )
    }
}
