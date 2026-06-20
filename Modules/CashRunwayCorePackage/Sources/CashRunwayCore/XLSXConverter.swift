import Foundation
import CoreXLSX

public enum XLSXConversionError: Error, LocalizedError {
    case noWorkbook
    case noWorksheet
    case headerNotFound

    public var errorDescription: String? {
        switch self {
        case .noWorkbook:
            return L10n.string("The XLSX file does not contain a workbook.")
        case .noWorksheet:
            return L10n.string("The XLSX file does not contain a worksheet.")
        case .headerNotFound:
            return L10n.string("Could not find a header row in the XLSX file.")
        }
    }
}

public enum XLSXConverter {
    public static func convertToCSV(data: Data) throws -> String {
        let file = try XLSXFile(data: data)
        let workbooks = try file.parseWorkbooks()
        guard let workbook = workbooks.first else {
            throw XLSXConversionError.noWorkbook
        }
        let worksheetPaths = try file.parseWorksheetPathsAndNames(workbook: workbook)
        guard let path = worksheetPaths.first?.path else {
            throw XLSXConversionError.noWorksheet
        }
        let worksheet = try file.parseWorksheet(at: path)
        let sharedStrings = try file.parseSharedStrings()
        let rows = worksheet.data?.rows ?? []

        var csvRows: [[String]] = []
        var headerRowIndex: Int?

        for (index, row) in rows.enumerated() {
            let values = rowValues(row, sharedStrings: sharedStrings)
            if headerRowIndex == nil && isHeaderRow(values) {
                headerRowIndex = index
                csvRows.append(values)
            } else if headerRowIndex != nil {
                csvRows.append(values)
            }
        }

        guard headerRowIndex != nil else {
            throw XLSXConversionError.headerNotFound
        }

        return csvRows
            .map { $0.map(escape).joined(separator: ",") }
            .joined(separator: "\n")
    }

    private static func rowValues(_ row: Row, sharedStrings: SharedStrings?) -> [String] {
        let sortedCells = row.cells.sorted {
            columnIndex($0.reference) < columnIndex($1.reference)
        }
        guard let lastReference = sortedCells.last?.reference else { return [] }
        let columnCount = columnIndex(lastReference) + 1
        var values = Array(repeating: "", count: columnCount)
        for cell in sortedCells {
            let index = columnIndex(cell.reference)
            values[index] = stringValue(cell, sharedStrings: sharedStrings)
        }
        return values
    }

    private static func stringValue(_ cell: Cell, sharedStrings: SharedStrings?) -> String {
        if let sharedStrings, let value = cell.stringValue(sharedStrings) {
            return value
        }
        if let inlineText = cell.inlineString?.text {
            return inlineText
        }
        return cell.value ?? ""
    }

    private static func columnIndex(_ reference: CellReference) -> Int {
        columnIndex(reference.column.value)
    }

    private static func columnIndex(_ letters: String) -> Int {
        var result = 0
        for character in letters.uppercased() {
            guard let ascii = character.asciiValue else { continue }
            result = result * 26 + Int(ascii - 64)
        }
        return result - 1
    }

    private static func isHeaderRow(_ values: [String]) -> Bool {
        let lowercased = values.map { $0.lowercased() }
        let keywords = [
            "дата", "date",
            "опис", "description",
            "сума", "amount",
            "картка", "card",
            "категорія", "category",
            "валюта", "currency"
        ]
        let matches = lowercased.filter { value in
            keywords.contains { value.contains($0) }
        }
        return matches.count >= 2
    }

    private static func escape(_ value: String) -> String {
        let escaped = value.replacingOccurrences(of: "\"", with: "\"\"")
        return "\"\(escaped)\""
    }
}
