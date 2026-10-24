import Foundation
import CoreXLSX
@testable import CashRunwayCore

// Throwaway evidence harness for PR 124. Invokes the PR's REAL exporter
// (MonthlyRetrospectiveExport + MonthlyRetrospectiveXLSX + ExportFile) on
// realistic sample snapshot data (2 currencies x 3 months, one approximate
// rate) and writes the artifacts using the PR's own file-naming code path.
// Sample USD figures are precomputed with the same half-up rounding
// convention the snapshot service uses (Decimal, .plain) — this harness only
// exercises the exporter, not the rate-resolution pipeline.

func isoDate(_ s: String) -> Date {
    let f = ISO8601DateFormatter()
    f.formatOptions = [.withInternetDateTime]
    return f.date(from: s)!
}

/// Half-up Decimal conversion of minor units by a stored rate string —
/// mirrors the snapshot service's rounding convention.
func baseMinor(_ minor: Int64, _ rate: String) -> Int64 {
    var product = Decimal(minor) * Decimal(string: rate)!
    var rounded = Decimal()
    NSDecimalRound(&rounded, &product, 0, .plain)
    return (rounded as NSDecimalNumber).int64Value
}

func snapshot(wallet: UUID, monthKey: Int, currency: CurrencyCode,
              income: Int64, expense: Int64, rate: String?,
              effective: Date?, source: String?, approximate: Bool) -> MonthlyUSDSnapshot {
    let saved = income - expense
    let incomeBase = rate.map { baseMinor(income, $0) }
    let expenseBase = rate.map { baseMinor(expense, $0) }
    let savedBase: Int64? = (incomeBase != nil && expenseBase != nil) ? incomeBase! - expenseBase! : nil
    return MonthlyUSDSnapshot(
        monthKey: monthKey,
        walletID: wallet,
        currencyCode: currency,
        incomeMinor: income,
        expenseMinor: expense,
        savedMinor: saved,
        baseCurrencyCode: .usd,
        incomeBaseMinor: incomeBase,
        expenseBaseMinor: expenseBase,
        savedBaseMinor: savedBase,
        rateDecimal: rate,
        rateEffectiveDate: effective,
        rateSource: source,
        isApproximate: approximate,
        updatedAt: isoDate("2026-07-01T19:00:00Z")
    )
}

// Sample data: UAH (primary) + EUR (secondary) wallets, 2026-04..2026-06.
// One approximate rate: April UAH rate is a nearest-earlier fallback
// (effective 2026-04-28, not the exact 2026-04-30 month end).
let uahRate = "0.024242424242424242424242424242424242" // ≈ 1/41.25, NBU official
let eurRate = "0.8696"
let uahWallet = UUID()
let eurWallet = UUID()

let snapshots: [MonthlyUSDSnapshot] = [
    snapshot(wallet: uahWallet, monthKey: 202604, currency: .uah, income: 74_800_000, expense: 62_250_000,
             rate: uahRate, effective: isoDate("2026-04-28T00:00:00Z"), source: "nbu-official", approximate: true),
    snapshot(wallet: eurWallet, monthKey: 202604, currency: .eur, income: 185_000, expense: 154_000,
             rate: eurRate, effective: isoDate("2026-04-30T00:00:00Z"), source: "nbu-official", approximate: false),
    snapshot(wallet: uahWallet, monthKey: 202605, currency: .uah, income: 80_240_000, expense: 64_115_000,
             rate: uahRate, effective: isoDate("2026-05-30T00:00:00Z"), source: "nbu-official", approximate: false),
    snapshot(wallet: eurWallet, monthKey: 202605, currency: .eur, income: 212_000, expense: 170_500,
             rate: eurRate, effective: isoDate("2026-05-30T00:00:00Z"), source: "nbu-official", approximate: false),
    snapshot(wallet: uahWallet, monthKey: 202606, currency: .uah, income: 89_370_000, expense: 70_522_000,
             rate: uahRate, effective: isoDate("2026-06-30T00:00:00Z"), source: "nbu-official", approximate: false),
    snapshot(wallet: eurWallet, monthKey: 202606, currency: .eur, income: 247_050, expense: 199_540,
             rate: eurRate, effective: isoDate("2026-06-30T00:00:00Z"), source: "nbu-official", approximate: false),
]

let rows = try MonthlyRetrospectiveExport.rows(from: snapshots)
let csv = MonthlyRetrospectiveExport.csv(rows: rows)

let firstMonth = rows.first!.month
let lastMonth = rows.last!.month
let csvName = ExportFile.name(from: firstMonth, to: lastMonth, format: .csv)
let xlsxName = ExportFile.name(from: firstMonth, to: lastMonth, format: .xlsx)
print("EXPORT_FILE_CSV=\(csvName)")
print("EXPORT_FILE_XLSX=\(xlsxName)")

let outDir = URL(fileURLWithPath: CommandLine.arguments.count > 1
    ? CommandLine.arguments[1]
    : "docs/evidence/pr-124/generated")

try FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)
try csv.write(to: outDir.appendingPathComponent(csvName), atomically: true, encoding: .utf8)

// XLSX via the PR's own writer, fed the same canonical cells.
let xlsxData = try MonthlyRetrospectiveXLSX.export(csvRows: [MonthlyRetrospectiveExport.Row.header] + rows.map { $0.cells })
try xlsxData.write(to: outDir.appendingPathComponent(xlsxName), options: .atomic)

print("XLSX_BYTES=\(xlsxData.count)")

// --- CoreXLSX round-trip verification (same reader the app uses for imports) ---
let file = try XLSXFile(data: xlsxData)
let workbooks = try file.parseWorkbooks()
let sheets = try file.parseWorksheetPathsAndNames(workbook: workbooks[0])
let worksheet = try file.parseWorksheet(at: sheets[0].path)
let parsedRows = worksheet.data?.rows ?? []

func cellsText(_ cells: [Cell]) -> [String] {
    var result: [String] = []
    guard var cursor = ColumnReference("A") else { return [] }
    for cell in cells.sorted(by: { $0.reference.column < $1.reference.column }) {
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

var roundTripOK = true
roundTripOK = roundTripOK && workbooks.count == 1
roundTripOK = roundTripOK && sheets.first?.name == "Retrospective"
roundTripOK = roundTripOK && parsedRows.count == rows.count + 1
let expectedMatrix = [MonthlyRetrospectiveExport.Row.header] + rows.map { $0.cells }
for (index, expected) in expectedMatrix.enumerated() {
    let got = cellsText(parsedRows[index].cells)
    if got != expected {
        roundTripOK = false
        print("ROUND_TRIP_MISMATCH row \(index): \(got) != \(expected)")
    }
}
print("ROUND_TRIP_STATUS=\(roundTripOK ? "OK" : "FAIL")")
print("ROUND_TRIP_ROWS=\(parsedRows.count) SHEET=\(sheets.first?.name ?? "?")")

print("CSV_BEGIN")
print(csv)
print("CSV_END")