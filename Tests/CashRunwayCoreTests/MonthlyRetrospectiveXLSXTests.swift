import Testing
import Foundation
import CoreXLSX
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

    /// CoreXLSX decode: numerics land in `cell.value`, inline strings in
    /// `cell.inlineString.text`; missing cells pad with "" so columns align.
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