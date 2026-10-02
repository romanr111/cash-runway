import Testing
import Foundation
import CoreXLSX
import ZIPFoundation
@testable import CashRunwayCore

/// Issue #123: the emitted XLSX must be a REAL spreadsheet — round-tripped
/// through CoreXLSX (the same reader the app uses for bank imports).
@Suite(.serialized)
struct MonthlyRetrospectiveXLSXTests {
    private static let header = [
        "Month", "Base Currency", "Currency", "Income", "Expenses", "Saved",
        "Income USD", "Expenses USD", "Saved USD",
        "Rate (Currency→USD)", "Rate Effective Date", "Rate Source", "Approximate",
    ]

    private static let dataRow = [
        "2026-06", "USD", "UAH", "41250.00", "31000.00", "10250.00",
        "1000.00", "750.00", "250.00",
        "0.024242424242424242424242424242424242", "2026-06-30", "nbu-official", "no",
    ]

    @Test func xlsxRoundTripsThroughCoreXLSX() throws {
        let data = try MonthlyRetrospectiveXLSX.export(csvRows: [Self.header, Self.dataRow])
        let file = try XLSXFile(data: data)
        let workbooks = try file.parseWorkbooks()
        #expect(workbooks.count == 1)
        let sheets = try file.parseWorksheetPathsAndNames(workbook: workbooks[0])
        #expect(sheets.first?.name == "Retrospective")
        let worksheet = try file.parseWorksheet(at: sheets[0].path)
        let rows = worksheet.data?.rows ?? []
        #expect(rows.count == 2)
        #expect(text(cells: rows[0].cells) == Self.header)
        #expect(text(cells: rows[1].cells) == Self.dataRow)
    }

    @Test func emptyFieldsStayAligned() throws {
        let rowWithGaps = Self.dataRow.enumerated().map { $0.offset == 9 ? "" : $0.element }
        let data = try MonthlyRetrospectiveXLSX.export(csvRows: [Self.header, rowWithGaps])
        let file = try XLSXFile(data: data)
        let workbooks = try file.parseWorkbooks()
        let sheets = try file.parseWorksheetPathsAndNames(workbook: workbooks[0])
        let worksheet = try file.parseWorksheet(at: sheets[0].path)
        let rows = worksheet.data?.rows ?? []
        let values = text(cells: rows[1].cells)
        #expect(values.count == Self.dataRow.count)
        #expect(values[9] == "")
    }

    @Test func unicodeAndQuotesSurvive() throws {
        let row = Self.dataRow.enumerated().map { $0.offset == 11 ? "say \"hi\" <&>" : $0.element }
        let data = try MonthlyRetrospectiveXLSX.export(csvRows: [Self.header, row])
        let file = try XLSXFile(data: data)
        let workbooks = try file.parseWorkbooks()
        let sheets = try file.parseWorksheetPathsAndNames(workbook: workbooks[0])
        let worksheet = try file.parseWorksheet(at: sheets[0].path)
        let values = text(cells: (worksheet.data?.rows ?? [])[1].cells)
        #expect(values[11] == "say \"hi\" <&>")
    }

    /// CoreXLSX leniency masked the missing cell type: CoreXLSX reads inline
    /// strings even without `t="inlineStr"`, but per ECMA-376 part 1 §18.3.1.4
    /// the `t` attribute of `<c>` defaults to `"number"`, so strict readers
    /// (real Excel, openpyxl) saw every text cell as empty. Assert the raw
    /// sheet XML directly so CoreXLSX's leniency cannot hide a regression.
    @Test func textCellsCarryInlineStrTypeInRawXML() throws {
        // Verify against the RAW sheet1.xml bytes: CoreXLSX is lenient about
        // the missing `t` attribute, strict readers (Excel, openpyxl) are not.
        let data = try MonthlyRetrospectiveXLSX.export(csvRows: [Self.header, Self.dataRow])
        let archiveURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("pr124-raw-\(UUID().uuidString).xlsx")
        try data.write(to: archiveURL)
        defer { try? FileManager.default.removeItem(at: archiveURL) }
        let archive = try Archive(url: archiveURL, accessMode: .read)
        guard let entry = archive.first(where: { $0.path == "xl/worksheets/sheet1.xml" }) else {
            Issue.record("sheet1.xml missing from the export archive")
            return
        }
        var xmlData = Data()
        _ = try archive.extract(entry, bufferSize: 65536) { chunk in
            xmlData.append(chunk)
        }
        let raw = String(decoding: xmlData, as: UTF8.self)

        // Structural sanity: both cell kinds are represented in the fixture.
        #expect(raw.contains("<is><t>"))
        #expect(raw.contains("<v>"))

        // Invariant: a cell whose body has inline-string markup must carry
        // t="inlineStr"; a `<v>` (numeric) cell must NOT.
        let inlineStrCell = /<c r="[A-Z]+\d+" t="inlineStr"><is><t>/
        let typedStringCells = raw.matches(of: inlineStrCell).count
        let stringCells = raw.components(separatedBy: "<is><t>").count - 1
        #expect(typedStringCells == stringCells,
                "every <is><t> cell must be typed t=\"inlineStr\" (\(typedStringCells)/\(stringCells))")

        let numericTyped = raw.matches(of: /<c [^>]*t="inlineStr"[^>]*><v>/).count
        #expect(numericTyped == 0, "t=\"inlineStr\" must not wrap a numeric `<v>` cell")
    }

    private func text(cells: [Cell]) -> [String] {
        // ColumnReference is Comparable only against itself (not Int) — pad
        // missing columns by advancing a cursor reference from "A".
        var result: [String] = []
        guard var cursor = ColumnReference("A") else { return [] }
        let sorted = cells.sorted { $0.reference.column < $1.reference.column }
        for cell in sorted {
            while cursor < cell.reference.column {
                result.append("")
                cursor = cursor.advanced(by: 1)
            }
            if let inline = cell.inlineString {
                result.append(inline.text ?? "")
            } else {
                result.append(cell.value ?? "")
            }
            cursor = cursor.advanced(by: 1)
        }
        return result
    }
}