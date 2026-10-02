import Foundation
import ZIPFoundation
import CoreXLSX

/// Issue #123: XLSX export of the retrospective via a minimal OOXML archive.
/// Inline strings only (no sharedStrings, no styles) — opens in Excel, Numbers,
/// Google Sheets, and round-trips through CoreXLSX (CI test asserts that).
public enum MonthlyRetrospectiveXLSX {
    // Minimal fixed OOXML parts. Sheet named "Retrospective".
    private static let contentTypes = """
    <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
    <Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types"><Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/><Default Extension="xml" ContentType="application/xml"/><Override PartName="/xl/workbook.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml"/><Override PartName="/xl/worksheets/sheet1.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml"/></Types>
    """

    private static let rootRels = """
    <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
    <Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"><Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="xl/workbook.xml"/></Relationships>
    """

    private static let workbook = """
    <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
    <workbook xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships"><sheets><sheet name="Retrospective" sheetId="1" r:id="rId1"/></sheets></workbook>
    """

    private static let workbookRels = """
    <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
    <Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"><Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet" Target="worksheets/sheet1.xml"/></Relationships>
    """

    /// Builds the worksheet XML from export rows (header first, then data).
    static func sheetXML(rows: [String]) -> String {
        let body = rows.enumerated().map { index, rowXML in
            "<row r=\"\(index + 1)\">\(rowXML)</row>"
        }.joined()
        return "<worksheet xmlns=\"http://schemas.openxmlformats.org/spreadsheetml/2006/main\"><sheetData>\(body)</sheetData></worksheet>"
    }

    /// One `<row>`'s cells: numeric-looking fields as numbers, everything else
    /// as inline strings. Empty fields render as empty inline strings so the
    /// column grid stays aligned.
    static func rowCells(_ values: [String], rowIndex: Int) -> String {
        values.enumerated().map { index, value in
            let reference = "\(columnLetter(index))\(rowIndex + 1)"
            return "<c r=\"\(reference)\">\(cellBody(value))</c>"
        }.joined()
    }

    static func cellBody(_ value: String) -> String {
        guard !value.isEmpty else { return "<is><t></t></is>" }
        if Double(value) != nil, value.first?.isNumber == true {
            return "<v>\(value)</v>"
        }
        return "<is><t>\(xmlEscape(value))</t></is>"
    }

    static func xmlEscape(_ value: String) -> String {
        value.replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
    }

    /// A1-style column letters (0 → "A", 26 → "AA").
    static func columnLetter(_ index: Int) -> String {
        var number = index
        var letters = ""
        repeat {
            letters = String(UnicodeScalar(UInt8(65 + number % 26))) + letters
            number = number / 26 - 1
        } while number >= 0
        return letters
    }

    /// Builds the .xlsx bytes for the export rows (header + data cells).
    public static func export(csvRows: [[String]]) throws -> Data {
        let rowXMLs = csvRows.enumerated().map { index, cells in
            rowCells(cells, rowIndex: index)
        }
        let sheet = sheetXML(rows: rowXMLs)

        let templateDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("retro-export-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: templateDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: templateDir) }

        let parts: [String: String] = [
            "[Content_Types].xml": contentTypes,
            "_rels/.rels": rootRels,
            "xl/workbook.xml": workbook,
            "xl/_rels/workbook.xml.rels": workbookRels,
            "xl/worksheets/sheet1.xml": sheet,
        ]
        for (relativePath, content) in parts {
            let fileURL = templateDir.appendingPathComponent(relativePath)
            try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try content.write(to: fileURL, atomically: true, encoding: .utf8)
        }

        let archiveURL = templateDir.appendingPathComponent("export.xlsx")
        let archive = try Archive(url: archiveURL, accessMode: .create)
        for relativePath in parts.keys.sorted() {
            try archive.addEntry(with: relativePath, relativeTo: templateDir)
        }
        return try Data(contentsOf: archiveURL)
    }
}