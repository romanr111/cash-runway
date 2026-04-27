import Foundation
import GRDB

public enum CSVPreset: String, CaseIterable, Sendable {
    case privatBank = "PrivatBank"
    case monobank = "Monobank"
    case generic = "Generic CSV"
}

public final class CSVService: @unchecked Sendable {
    private let repository: LedgerRepository

    public init(repository: LedgerRepository) {
        self.repository = repository
    }

    public func preview(data: Data) throws -> CSVImportPreview {
        let text = try decode(data: data)
        let rows = parseRows(text)
        guard let headers = rows.first else { throw LedgerError.validation("CSV file is empty.") }
        return CSVImportPreview(headers: headers, sampleRows: Array(rows.dropFirst().prefix(5)))
    }

    public func detectPreset(headers: [String]) -> CSVPreset {
        let lowercased = Set(headers.map { $0.lowercased() })
        if lowercased.contains("дата операції") || lowercased.contains("сума в грн") {
            return .privatBank
        }
        if lowercased.contains("description") && lowercased.contains("mcc") {
            return .monobank
        }
        return .generic
    }

    public func importCSV(data: Data, fileName: String, mapping: CSVImportMapping) throws -> CSVImportResult {
        let text = try decode(data: data)
        let rows = parseRows(text)
        guard let headers = rows.first else { throw LedgerError.validation("CSV file is empty.") }
        let headerIndex = Dictionary(uniqueKeysWithValues: headers.enumerated().map { ($1, $0) })
        let now = Date()
        var affectedMonths = Set<Int>()
        var validDrafts: [TransactionDraft] = []
        var invalidRows = 0
        var rowErrors: [CSVRowError] = []

        for (offset, row) in rows.dropFirst().enumerated() {
            do {
                let date = try parseDate(from: cell(row, mapping.dateColumn, headerIndex))
                let amount = try parseAmount(row: row, mapping: mapping, headerIndex: headerIndex)
                let categoryID = try parseCategoryID(row: row, mapping: mapping, headerIndex: headerIndex)
                let labels = parseLabels(row: row, mapping: mapping, headerIndex: headerIndex)
                validDrafts.append(
                    TransactionDraft(
                        kind: mapping.defaultKind,
                        walletID: mapping.walletID,
                        amountMinor: amount,
                        occurredAt: date,
                        categoryID: categoryID,
                        labelIDs: labels,
                        merchant: cell(row, mapping.merchantColumn, headerIndex),
                        note: cell(row, mapping.noteColumn, headerIndex),
                        source: .importCSV
                    )
                )
                affectedMonths.insert(DateKeys.monthKey(for: date))
            } catch {
                invalidRows += 1
                if rowErrors.count < 20 {
                    rowErrors.append(CSVRowError(rowNumber: offset + 2, message: error.localizedDescription))
                }
            }
        }

        var job = ImportJob(
            id: UUID(),
            sourceName: detectPreset(headers: headers).rawValue,
            fileName: fileName,
            status: .validated,
            totalRows: max(rows.count - 1, 0),
            validRows: validDrafts.count,
            invalidRows: invalidRows,
            startedAt: now,
            finishedAt: nil,
            errorSummary: invalidRows > 0 ? "\(invalidRows) rows failed validation." : nil
        )

        try repository.databaseManager.dbQueue.write { db in
            try db.execute(
                sql: """
                INSERT INTO import_jobs (id, source_name, file_name, status, total_rows, valid_rows, invalid_rows, started_at, finished_at, error_summary)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                """,
                arguments: [
                    job.id.uuidString, job.sourceName, job.fileName, job.status.rawValue, job.totalRows,
                    job.validRows, job.invalidRows, job.startedAt, job.finishedAt, job.errorSummary,
                ]
            )
        }

        do {
            for batch in stride(from: 0, to: validDrafts.count, by: 500).map({ Array(validDrafts[$0..<min($0 + 500, validDrafts.count)]) }) {
                try repository.appendImportedTransactions(batch)
            }
            try repository.finalizeImport(
                jobID: job.id,
                affectedMonths: affectedMonths,
                validRows: validDrafts.count,
                invalidRows: invalidRows,
                errorSummary: job.errorSummary
            )
        } catch {
            try? repository.failImport(jobID: job.id, errorSummary: error.localizedDescription)
            throw error
        }

        job.status = .committed
        job.finishedAt = Date()
        return CSVImportResult(job: job, insertedTransactions: validDrafts.count, affectedMonths: affectedMonths, rowErrors: rowErrors)
    }

    public func exportCSV(query: TransactionQuery = .init()) throws -> String {
        let transactions = try repository.transactions(query: query)
        let header = ["date", "wallet", "type", "amount", "category", "labels", "merchant", "note", "source"]
        let lines = transactions.map { item in
            [
                item.occurredAt.formatted(.iso8601.year().month().day()),
                item.walletName,
                item.kind.rawValue,
                MoneyFormatter.plainString(from: item.amountMinor),
                item.categoryName ?? "",
                item.labels.map(\.name).joined(separator: "|"),
                item.merchant,
                item.note,
                item.source.rawValue,
            ].map(escape).joined(separator: ",")
        }
        return ([header.joined(separator: ",")] + lines).joined(separator: "\n")
    }

    private func decode(data: Data) throws -> String {
        if let utf8 = String(data: data, encoding: .utf8) {
            return utf8
        }
        let cfEncoding = CFStringConvertEncodingToNSStringEncoding(CFStringEncoding(CFStringEncodings.windowsCyrillic.rawValue))
        if let cp1251 = String(data: data, encoding: String.Encoding(rawValue: cfEncoding)) {
            return cp1251
        }
        throw LedgerError.validation("Unsupported CSV encoding.")
    }

    private func parseRows(_ text: String) -> [[String]] {
        let delimiter = detectDelimiter(in: text)
        return text
            .split(whereSeparator: \.isNewline)
            .map { line in line.split(separator: Character(delimiter), omittingEmptySubsequences: false).map { String($0).trimmingCharacters(in: .whitespaces) } }
    }

    private func detectDelimiter(in text: String) -> String {
        let sample = text.split(whereSeparator: \.isNewline).prefix(3).joined(separator: "\n")
        let candidates = [",", ";", "\t"]
        return candidates.max { lhs, rhs in
            sample.components(separatedBy: lhs).count < sample.components(separatedBy: rhs).count
        } ?? ","
    }

    private func cell(_ row: [String], _ header: String?, _ headerIndex: [String: Int]) -> String {
        guard let header, let index = headerIndex[header], row.indices.contains(index) else { return "" }
        return row[index]
    }

    private func parseDate(from input: String) throws -> Date {
        let isoDateFormatter = ISO8601DateFormatter()
        isoDateFormatter.formatOptions = [.withFullDate]
        if let dateOnly = isoDateFormatter.date(from: input) {
            return dateOnly
        }
        if let iso = ISO8601DateFormatter().date(from: input) {
            return iso
        }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "uk_UA")
        formatter.dateFormat = "dd.MM.yyyy"
        if let date = formatter.date(from: input) {
            return date
        }
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        if let date = formatter.date(from: input) {
            return date
        }
        throw LedgerError.validation("Unsupported date format.")
    }

    private func parseAmount(row: [String], mapping: CSVImportMapping, headerIndex: [String: Int]) throws -> Int64 {
        if let amountColumn = mapping.amountColumn {
            return try abs(MoneyFormatter.parseMinorUnits(cell(row, amountColumn, headerIndex)))
        }
        let debit = try? MoneyFormatter.parseMinorUnits(cell(row, mapping.debitColumn, headerIndex))
        let credit = try? MoneyFormatter.parseMinorUnits(cell(row, mapping.creditColumn, headerIndex))
        if let debit, debit != 0 { return abs(debit) }
        if let credit, credit != 0 { return abs(credit) }
        throw LedgerError.validation("Could not parse amount.")
    }

    private func parseCategoryID(row: [String], mapping: CSVImportMapping, headerIndex: [String: Int]) throws -> UUID? {
        let categories = try repository.categories(kind: mapping.defaultKind == .income ? .income : .expense)
        let raw = cell(row, mapping.categoryColumn, headerIndex)
        if raw.isEmpty {
            return fallbackCategoryID(in: categories, for: mapping.defaultKind)
        }
        return categories.first(where: { $0.name.caseInsensitiveCompare(raw) == .orderedSame })?.id
            ?? fallbackCategoryID(in: categories, for: mapping.defaultKind)
    }

    private func fallbackCategoryID(in categories: [Category], for kind: TransactionDraft.Kind) -> UUID? {
        let fallbackName = kind == .income ? "Other Income" : "Other Expense"
        return categories.first(where: { $0.name == fallbackName })?.id ?? categories.first?.id
    }

    private func parseLabels(row: [String], mapping: CSVImportMapping, headerIndex: [String: Int]) -> [UUID] {
        let raw = cell(row, mapping.labelsColumn, headerIndex)
        guard !raw.isEmpty else { return [] }
        let names = raw.split(separator: "|").map { $0.trimmingCharacters(in: .whitespaces) }
        let availableLabels = (try? repository.labels()) ?? []
        return names.compactMap { name in availableLabels.first(where: { $0.name.caseInsensitiveCompare(name) == .orderedSame })?.id }
    }

    private func escape(_ value: String) -> String {
        let escaped = value.replacingOccurrences(of: "\"", with: "\"\"")
        return "\"\(escaped)\""
    }
}
