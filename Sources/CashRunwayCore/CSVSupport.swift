import Foundation
import GRDB

public enum CSVPreset: String, CaseIterable, Sendable {
    case cashRunwayWallet = "Cash Runway Wallet"
    case privatBank = "PrivatBank"
    case monobank = "Monobank"
    case generic = "Generic CSV"
}

public final class CSVService: @unchecked Sendable {
    private let repository: CashRunwayRepository

    public init(repository: CashRunwayRepository) {
        self.repository = repository
    }

    public func preview(data: Data) throws -> CSVImportPreview {
        let text = try decode(data: data)
        let rows = parseRows(text)
        guard let headers = rows.first else { throw CashRunwayError.validation("CSV file is empty.") }
        return CSVImportPreview(headers: headers, sampleRows: Array(rows.dropFirst().prefix(5)), totalRows: max(rows.count - 1, 0))
    }

    public func detectPreset(headers: [String]) -> CSVPreset {
        let lowercased = Set(headers.map { $0.lowercased() })
        if lowercased.isSuperset(of: ["date", "wallet", "type", "category name", "amount", "currency", "note", "labels", "author"]) {
            return .cashRunwayWallet
        }
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
        guard let headers = rows.first else { throw CashRunwayError.validation("CSV file is empty.") }
        let headerIndex = Dictionary(uniqueKeysWithValues: headers.enumerated().map { ($1, $0) })
        let now = Date()
        var affectedMonths = Set<Int>()
        var validDrafts: [TransactionDraft] = []
        var invalidRows = 0
        var rowErrors: [CSVRowError] = []
        let wallets = try repository.wallets()
        var expenseCategories = try repository.categories(kind: .expense)
        var incomeCategories = try repository.categories(kind: .income)
        var availableLabels = try repository.labels()

        for (offset, row) in rows.dropFirst().enumerated() {
            do {
                let date = try parseDate(from: cell(row, mapping.dateColumn, headerIndex))
                try validateCurrency(row: row, mapping: mapping, headerIndex: headerIndex)
                let signedAmount = try parseAmount(row: row, mapping: mapping, headerIndex: headerIndex)
                let kind = parseKind(row: row, mapping: mapping, headerIndex: headerIndex, signedAmount: signedAmount)
                let categoryID = try resolveCategoryID(
                    row: row,
                    mapping: mapping,
                    headerIndex: headerIndex,
                    kind: kind,
                    expenseCategories: &expenseCategories,
                    incomeCategories: &incomeCategories
                )
                let labels = parseLabels(row: row, mapping: mapping, headerIndex: headerIndex, availableLabels: &availableLabels)
                validDrafts.append(
                    TransactionDraft(
                        kind: kind,
                        walletID: parseWalletID(row: row, mapping: mapping, headerIndex: headerIndex, wallets: wallets),
                        amountMinor: abs(signedAmount),
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
        let transactions = try repository.transactions(query: query, limit: nil)
        let header = ["Date", "Wallet", "Type", "Category name", "Amount", "Currency", "Note", "Labels", "Author"]
        let dateFormatter = ISO8601DateFormatter()
        let lines = transactions.map { item in
            [
                dateFormatter.string(from: item.occurredAt),
                item.walletName,
                item.kind.rawValue.capitalized,
                item.categoryName ?? "",
                MoneyFormatter.plainString(from: item.amountMinor),
                "UAH",
                item.note,
                item.labels.map(\.name).joined(separator: "|"),
                "",
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
        throw CashRunwayError.validation("Unsupported CSV encoding.")
    }

    private func parseRows(_ text: String) -> [[String]] {
        let delimiter = detectDelimiter(in: text)
        var rows: [[String]] = []
        var row: [String] = []
        var field = ""
        var isQuoted = false
        var index = text.startIndex

        func appendField() {
            row.append(field.trimmingCharacters(in: .whitespaces))
            field = ""
        }

        func appendRowIfNeeded() {
            if !row.isEmpty || !field.isEmpty {
                appendField()
                rows.append(row)
                row = []
            }
        }

        while index < text.endIndex {
            let character = text[index]
            let nextIndex = text.index(after: index)
            if character == "\"" {
                if isQuoted, nextIndex < text.endIndex, text[nextIndex] == "\"" {
                    field.append(character)
                    index = text.index(after: nextIndex)
                } else {
                    isQuoted.toggle()
                    index = nextIndex
                }
            } else if String(character) == delimiter, !isQuoted {
                appendField()
                index = nextIndex
            } else if character == "\n", !isQuoted {
                appendRowIfNeeded()
                index = nextIndex
            } else if character == "\r", !isQuoted {
                appendRowIfNeeded()
                if nextIndex < text.endIndex, text[nextIndex] == "\n" {
                    index = text.index(after: nextIndex)
                } else {
                    index = nextIndex
                }
            } else {
                field.append(character)
                index = nextIndex
            }
        }
        appendRowIfNeeded()
        return rows
    }

    private func detectDelimiter(in text: String) -> String {
        let sample = text.split(whereSeparator: \.isNewline).prefix(3).joined(separator: "\n")
        let candidates = [",", ";", "\t"]
        return candidates.max { lhs, rhs in
            delimiterCount(lhs, in: sample) < delimiterCount(rhs, in: sample)
        } ?? ","
    }

    private func delimiterCount(_ delimiter: String, in text: String) -> Int {
        var count = 0
        var isQuoted = false
        var index = text.startIndex
        while index < text.endIndex {
            let character = text[index]
            let nextIndex = text.index(after: index)
            if character == "\"" {
                if isQuoted, nextIndex < text.endIndex, text[nextIndex] == "\"" {
                    index = text.index(after: nextIndex)
                } else {
                    isQuoted.toggle()
                    index = nextIndex
                }
            } else {
                if String(character) == delimiter, !isQuoted {
                    count += 1
                }
                index = nextIndex
            }
        }
        return count
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
        let isoLikeFormatter = DateFormatter()
        isoLikeFormatter.locale = Locale(identifier: "en_US_POSIX")
        for format in ["yyyy-MM-dd'T'HH:mm:ss.SSSXXXXX", "yyyy-MM-dd'T'HH:mm:ssXXXXX", "yyyy-MM-dd'T'HH:mm:ss"] {
            isoLikeFormatter.dateFormat = format
            if let date = isoLikeFormatter.date(from: input) {
                return date
            }
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
        throw CashRunwayError.validation("Unsupported date format.")
    }

    private func parseAmount(row: [String], mapping: CSVImportMapping, headerIndex: [String: Int]) throws -> Int64 {
        if let amountColumn = mapping.amountColumn {
            return try MoneyFormatter.parseMinorUnits(cell(row, amountColumn, headerIndex))
        }
        let debit = try? MoneyFormatter.parseMinorUnits(cell(row, mapping.debitColumn, headerIndex))
        let credit = try? MoneyFormatter.parseMinorUnits(cell(row, mapping.creditColumn, headerIndex))
        if let debit, debit != 0 { return -abs(debit) }
        if let credit, credit != 0 { return abs(credit) }
        throw CashRunwayError.validation("Could not parse amount.")
    }

    private func parseKind(row: [String], mapping: CSVImportMapping, headerIndex: [String: Int], signedAmount: Int64) -> TransactionDraft.Kind {
        let raw = cell(row, mapping.typeColumn, headerIndex).lowercased()
        if raw == "income" || raw == "inflow" || raw == "credit" {
            return .income
        }
        if raw == "expense" || raw == "outflow" || raw == "debit" {
            return .expense
        }
        if raw == "transfer" {
            return .transfer
        }
        if signedAmount < 0 {
            return .expense
        }
        if signedAmount > 0, mapping.typeColumn != nil {
            return .income
        }
        return mapping.defaultKind
    }

    private func parseWalletID(row: [String], mapping: CSVImportMapping, headerIndex: [String: Int], wallets: [Wallet]) -> UUID {
        let raw = cell(row, mapping.walletColumn, headerIndex)
        guard !raw.isEmpty else { return mapping.walletID }
        return wallets.first(where: { $0.name.caseInsensitiveCompare(raw) == .orderedSame })?.id ?? mapping.walletID
    }

    private func validateCurrency(row: [String], mapping: CSVImportMapping, headerIndex: [String: Int]) throws {
        let raw = cell(row, mapping.currencyColumn, headerIndex)
        guard !raw.isEmpty else { return }
        let normalized = raw.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard normalized == "UAH" || normalized == "₴" || normalized == "ГРН" else {
            throw CashRunwayError.validation("Unsupported currency.")
        }
    }

    private func resolveCategoryID(
        row: [String],
        mapping: CSVImportMapping,
        headerIndex: [String: Int],
        kind: TransactionDraft.Kind,
        expenseCategories: inout [Category],
        incomeCategories: inout [Category]
    ) throws -> UUID? {
        guard kind != .transfer else { return nil }
        let categoryName = normalizedCategoryName(cell(row, mapping.categoryColumn, headerIndex))
        let categories = kind == .income ? incomeCategories : expenseCategories
        guard let categoryName else {
            return fallbackCategoryID(in: categories, for: kind)
        }
        if let existing = categories.first(where: { normalizedCategoryName($0.name)?.caseInsensitiveCompare(categoryName) == .orderedSame }) {
            return existing.id
        }

        let createdCategory = try createImportedCategory(named: categoryName, kind: kind, existingCategories: categories)
        if kind == .income {
            incomeCategories.append(createdCategory)
        } else {
            expenseCategories.append(createdCategory)
        }
        return createdCategory.id
    }

    private func createImportedCategory(named name: String, kind: TransactionDraft.Kind, existingCategories: [Category]) throws -> Category {
        let fallbackName = kind == .income ? "Other Income" : "Other Expense"
        let fallback = existingCategories.first(where: { $0.name == fallbackName }) ?? existingCategories.first
        let appearance = importedCategoryAppearance(for: name, kind: kind)
        let now = Date()
        let category = Category(
            id: UUID(),
            name: name,
            kind: kind == .income ? .income : .expense,
            iconName: appearance?.iconName ?? fallback?.iconName,
            colorHex: appearance?.colorHex ?? fallback?.colorHex,
            parentID: nil,
            isSystem: false,
            isArchived: false,
            sortOrder: (existingCategories.map(\.sortOrder).max() ?? 0) + 1,
            createdAt: now,
            updatedAt: now
        )
        try repository.saveCategory(category)
        return category
    }

    private func importedCategoryAppearance(for name: String, kind: TransactionDraft.Kind) -> ImportedCategoryAppearance? {
        let normalizedName = normalizedKeywordText(name)
        let rules = kind == .income ? Self.incomeAppearanceRules : Self.expenseAppearanceRules
        return rules.first { rule in
            rule.keywords.contains { normalizedName.contains($0) }
        }.map { ImportedCategoryAppearance(iconName: $0.iconName, colorHex: $0.colorHex) }
    }

    private func normalizedKeywordText(_ input: String) -> String {
        input
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "uk_UA"))
            .lowercased()
            .replacingOccurrences(of: "&", with: " ")
            .replacingOccurrences(of: "-", with: " ")
            .replacingOccurrences(of: "_", with: " ")
    }

    private func normalizedCategoryName(_ input: String) -> String? {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private func fallbackCategoryID(in categories: [Category], for kind: TransactionDraft.Kind) -> UUID? {
        let fallbackName = kind == .income ? "Other Income" : "Other Expense"
        return categories.first(where: { $0.name == fallbackName })?.id ?? categories.first?.id
    }

    private struct ImportedCategoryAppearance {
        var iconName: String
        var colorHex: String
    }

    private struct ImportedCategoryAppearanceRule {
        var keywords: [String]
        var iconName: String
        var colorHex: String
    }

    private static let expenseAppearanceRules: [ImportedCategoryAppearanceRule] = [
        .init(keywords: ["relationship", "dating", "romance", "love", "отношен", "стосунк", "кохан"], iconName: "heart.fill", colorHex: "#FF5E57"),
        .init(keywords: ["food", "drink", "grocer", "product", "supermarket", "продукт", "еда", "їжа", "харч", "напит", "напій"], iconName: "fork.knife", colorHex: "#B78B4A"),
        .init(keywords: ["restaurant", "cafe", "coffee", "ресторан", "кафе", "кофе", "кава"], iconName: "cup.and.saucer.fill", colorHex: "#64D1D5"),
        .init(keywords: ["transport", "taxi", "metro", "bus", "tram", "транспорт", "такси", "таксі", "метро", "автобус", "проезд", "проїзд"], iconName: "tram.fill", colorHex: "#FFC400"),
        .init(keywords: ["rent", "housing", "home", "apartment", "аренд", "оренд", "жиль", "житл", "квартир"], iconName: "house.fill", colorHex: "#E5862F"),
        .init(keywords: ["bill", "utilit", "electric", "water", "gas", "internet", "счет", "счёт", "рахунк", "коммун", "комун", "свет", "світло", "вода", "газ", "інтернет"], iconName: "bolt.fill", colorHex: "#6FD03B"),
        .init(keywords: ["health", "doctor", "pharmacy", "clinic", "мед", "врач", "лікар", "аптек", "здоров"], iconName: "cross.case.fill", colorHex: "#E96176"),
        .init(keywords: ["shopping", "clothes", "market", "покуп", "магазин", "одеж", "одяг"], iconName: "bag.fill", colorHex: "#5FD4BF"),
        .init(keywords: ["entertain", "movie", "cinema", "game", "развлеч", "кіно", "кино", "ігри", "игры"], iconName: "theatermasks.fill", colorHex: "#FFA600"),
        .init(keywords: ["education", "school", "course", "book", "обуч", "образов", "освіт", "навчан", "курс", "книг"], iconName: "graduationcap.fill", colorHex: "#4A80C1"),
        .init(keywords: ["travel", "flight", "hotel", "trip", "поезд", "подорож", "путеше", "отель", "готел", "авиа", "авіа"], iconName: "airplane", colorHex: "#EE5DA7"),
        .init(keywords: ["gift", "present", "подар"], iconName: "gift.fill", colorHex: "#FF5E57"),
        .init(keywords: ["pet", "cat", "dog", "animal", "питом", "живот", "тварин", "кіт", "кот", "собак"], iconName: "pawprint.fill", colorHex: "#B78B4A"),
    ]

    private static let incomeAppearanceRules: [ImportedCategoryAppearanceRule] = [
        .init(keywords: ["salary", "wage", "payroll", "зарплат", "заробіт", "заробот"], iconName: "banknote.fill", colorHex: "#2AAAD2"),
        .init(keywords: ["bonus", "бонус", "прем"], iconName: "crown.fill", colorHex: "#F7A72A"),
        .init(keywords: ["gift", "present", "подар"], iconName: "gift.fill", colorHex: "#FF5E57"),
        .init(keywords: ["refund", "cashback", "reimbursement", "возврат", "поверн", "кешбек"], iconName: "arrow.uturn.backward.circle.fill", colorHex: "#16C790"),
        .init(keywords: ["freelance", "project", "side", "contract", "фриланс", "проект", "контракт"], iconName: "briefcase.fill", colorHex: "#2AAAD2"),
    ]

    private func parseLabels(row: [String], mapping: CSVImportMapping, headerIndex: [String: Int], availableLabels: inout [Label]) -> [UUID] {
        let raw = cell(row, mapping.labelsColumn, headerIndex)
        guard !raw.isEmpty else { return [] }
        let separator: Character? = if raw.contains("|") {
            "|"
        } else if raw.contains(";") {
            ";"
        } else {
            nil
        }
        let names = if let separator {
            raw.split(separator: separator).map { $0.trimmingCharacters(in: .whitespaces) }
        } else {
            [raw.trimmingCharacters(in: .whitespaces)]
        }
        return names.compactMap { name in
            if let existing = availableLabels.first(where: { $0.name.caseInsensitiveCompare(name) == .orderedSame }) {
                return existing.id
            }
            let created = try? createImportedLabel(named: name)
            if let created {
                availableLabels.append(created)
            }
            return created?.id
        }
    }

    private func createImportedLabel(named name: String) throws -> Label {
        let now = Date()
        let label = Label(
            id: UUID(),
            name: name,
            colorHex: "#60788A",
            createdAt: now,
            updatedAt: now
        )
        try repository.saveLabel(label)
        return label
    }

    private func escape(_ value: String) -> String {
        let escaped = value.replacingOccurrences(of: "\"", with: "\"\"")
        return "\"\(escaped)\""
    }
}
