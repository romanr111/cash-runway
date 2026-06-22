import Foundation
import SwiftUI
#if canImport(CashRunwayCore)
import CashRunwayCore
#endif

@MainActor
@Observable
final class CSVImportCoordinator: Identifiable {
    let id = UUID()
    let model: CashRunwayAppModel

    var importData = Data()
    var importFileName = ""
    var importPreview = CSVImportPreview(headers: [], sampleRows: [], totalRows: 0)
    var importMapping = CSVImportMapping(
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
    var importPreset: CSVPreset = .generic
    var isImportPreparing = false
    var importPreparationProgress = 0.0
    var importPreparationStatus = ""
    var importPreparationError: String?

    var importResult: CSVImportResult?
    var importError: String?
    var isImporting = false
    var isAdvancedMappingExpanded = false
    var importExpensesOnly = false

    var rowFilter: CSVImportRowFilter {
        importExpensesOnly ? .expensesOnly : .allTransactions
    }

    init(model: CashRunwayAppModel) {
        self.model = model
    }

    func prepareImport(from url: URL) {
        let fileName = url.lastPathComponent.isEmpty ? "import.csv" : url.lastPathComponent

        importData = Data()
        importFileName = fileName
        importPreview = CSVImportPreview(headers: [], sampleRows: [], totalRows: 0)
        importExpensesOnly = false
        importPreset = .generic
        importMapping = defaultMapping(headers: [], preset: .generic)
        importPreparationError = nil
        importPreparationProgress = 0.12
        importPreparationStatus = "Opening selected file..."
        isImportPreparing = true

        Task { @MainActor in
            do {
                importPreparationProgress = 0.55
                importPreparationStatus = "Reading CSV rows..."
                let preparedImport = try await model.prepareCSVImport(from: url)
                importData = preparedImport.data
                importPreview = preparedImport.preview
                importPreset = preparedImport.preset
                importMapping = defaultMapping(headers: preparedImport.preview.headers, preset: preparedImport.preset)
                importPreparationProgress = 1.0
                importPreparationStatus = "Ready to review."
                isImportPreparing = false
            } catch {
                importPreparationError = error.localizedDescription
                importPreparationProgress = 0.0
                importPreparationStatus = ""
                isImportPreparing = false
            }
        }
    }

    func startImport() {
        guard !isImporting else { return }
        importError = nil
        isImporting = true
        Task { @MainActor in
            await Task.yield()
            do {
                importResult = try await model.importCSV(
                    data: importData,
                    fileName: importFileName,
                    mapping: importMapping,
                    rowFilter: rowFilter
                )
            } catch {
                importError = error.localizedDescription
            }
            isImporting = false
        }
    }

    private func defaultMapping(headers: [String], preset: CSVPreset) -> CSVImportMapping {
        model.csvService.defaultMapping(
            headers: headers,
            preset: preset,
            walletID: model.wallets.first?.id
        )
    }
}
