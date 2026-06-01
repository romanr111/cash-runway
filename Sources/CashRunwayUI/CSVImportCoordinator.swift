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

    init(model: CashRunwayAppModel) {
        self.model = model
    }

    func prepareImport(from url: URL) {
        let fileName = url.lastPathComponent.isEmpty ? "import.csv" : url.lastPathComponent

        importData = Data()
        importFileName = fileName
        importPreview = CSVImportPreview(headers: [], sampleRows: [], totalRows: 0)
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
                importResult = try await model.importCSV(data: importData, fileName: importFileName, mapping: importMapping)
            } catch {
                importError = error.localizedDescription
            }
            isImporting = false
        }
    }

    private func defaultMapping(headers: [String], preset: CSVPreset) -> CSVImportMapping {
        guard let walletID = model.wallets.first?.id else {
            return CSVImportMapping(
                dateColumn: headers.first ?? "",
                amountColumn: nil,
                debitColumn: nil,
                creditColumn: nil,
                merchantColumn: nil,
                noteColumn: nil,
                categoryColumn: nil,
                labelsColumn: nil,
                walletID: nil,
                defaultKind: .expense,
                typeColumn: nil,
                walletColumn: nil,
                currencyColumn: nil,
                authorColumn: nil
            )
        }
        let dateColumn = header(named: ["Дата операції", "Date", "date"], in: headers) ?? headers.first ?? ""
        let amountColumn = header(named: ["Сума в грн", "Amount", "amount", "sum"], in: headers)
        let debitColumn = header(named: ["Debit", "debit", "Витрати"], in: headers)
        let creditColumn = header(named: ["Credit", "credit", "Надходження"], in: headers)
        let typeColumn = header(named: ["Type", "type"], in: headers)
        let walletColumn = header(named: ["Wallet", "wallet"], in: headers)
        let currencyColumn = header(named: ["Currency", "currency"], in: headers)
        let merchantColumn = header(named: ["Description", "description", "Merchant", "merchant", "Призначення"], in: headers)
        let noteColumn = header(named: ["Comment", "comment", "Note", "note"], in: headers)
        let categoryColumn = header(named: ["Category", "category", "Category name", "category name"], in: headers)
        let labelsColumn = header(named: ["Labels", "labels", "Tags"], in: headers)
        let authorColumn = header(named: ["Author", "author"], in: headers)

        return CSVImportMapping(
            dateColumn: dateColumn,
            amountColumn: amountColumn,
            debitColumn: preset == .generic ? debitColumn : nil,
            creditColumn: preset == .generic ? creditColumn : nil,
            merchantColumn: merchantColumn,
            noteColumn: noteColumn,
            categoryColumn: categoryColumn,
            labelsColumn: labelsColumn,
            walletID: walletID,
            defaultKind: .expense,
            typeColumn: typeColumn,
            walletColumn: walletColumn,
            currencyColumn: currencyColumn,
            authorColumn: authorColumn
        )
    }

    private func header(named candidates: [String], in headers: [String]) -> String? {
        headers.first { header in
            candidates.contains { $0.caseInsensitiveCompare(header) == .orderedSame }
        }
    }
}
