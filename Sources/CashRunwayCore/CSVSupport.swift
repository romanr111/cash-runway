import Foundation
import GRDB
import CryptoKit

public enum CSVPreset: String, CaseIterable, Sendable {
    case cashRunwayWallet = "Cash Runway Wallet"
    case privatBank = "PrivatBank"
    case monobank = "Monobank"
    case generic = "Generic CSV"
}

private struct ImportFingerprintInput {
    let sourceName: String
    let walletID: UUID
    let kind: TransactionDraft.Kind
    let occurredAt: Date
    let amountMinor: Int64
    let merchant: String?
    let note: String?
    let categoryName: String?
    let currency: String?
}

private func importFingerprint(_ input: ImportFingerprintInput) -> String {
    let normalizedMerchant = (input.merchant ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    let normalizedNote = (input.note ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    let normalizedCategory = (input.categoryName ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    let normalizedCurrency = (input.currency ?? "").trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
    let kindString = input.kind.rawValue
    let dateString = ISO8601DateFormatter().string(from: input.occurredAt)
    let components = [
        input.sourceName,
        input.walletID.uuidString,
        kindString,
        dateString,
        String(input.amountMinor),
        normalizedMerchant,
        normalizedNote,
        normalizedCategory,
        normalizedCurrency
    ]
    let input = components.joined(separator: "|")
    let hash = SHA256.hash(data: Data(input.utf8))
    return hash.compactMap { String(format: "%02x", $0) }.joined()
}

// CSV import/export intentionally keeps its parser and category heuristics together.
// swiftlint:disable:next type_body_length
public final class CSVService: @unchecked Sendable {
    private let repository: CashRunwayRepository

    public init(repository: CashRunwayRepository) {
        self.repository = repository
    }

    public func preview(data: Data) throws -> CSVImportPreview {
        let text = try decode(data: data)
        let rows = parseRows(text)
        guard let headers = rows.first else { throw CashRunwayError.validation(L10n.string("CSV file is empty.")) }
        return CSVImportPreview(
            headers: headers,
            sampleRows: Array(rows.dropFirst().prefix(5)),
            totalRows: max(rows.count - 1, 0)
        )
    }

    public func detectPreset(headers: [String]) -> CSVPreset {
        let lowercased = Set(headers.map { $0.lowercased() })
        if lowercased.isSuperset(of: [
            "date",
            "wallet",
            "type",
            "category name",
            "amount",
            "currency",
            "note",
            "labels",
            "author"
        ]) {
            return .cashRunwayWallet
        }
        if lowercased.contains("дата операції") || lowercased.contains("сума в грн") {
            return .privatBank
        }
        let hasPrivatBankDate = lowercased.contains { $0.contains("дата") }
        let hasPrivatBankDescription = lowercased.contains { $0.contains("опис операції") }
        let hasPrivatBankCardAmount = lowercased.contains { $0.contains("сума в валюті картки") }
        if hasPrivatBankDate && hasPrivatBankDescription && hasPrivatBankCardAmount {
            return .privatBank
        }
        if lowercased.contains("description") && lowercased.contains("mcc") {
            return .monobank
        }
        let hasUkrainianDate = lowercased.contains { $0.contains("дата і час операції") || $0.contains("дата i час операції") }
        let hasUkrainianDetails = lowercased.contains { $0.contains("деталі операції") }
        let hasUkrainianCardAmount = lowercased.contains { $0.contains("сума в валюті картки") }
        if hasUkrainianDate && hasUkrainianDetails && lowercased.contains("mcc") && hasUkrainianCardAmount {
            return .monobank
        }
        return .generic
    }

    public func importCSV(data: Data, fileName: String, mapping: CSVImportMapping) throws -> CSVImportResult {
        let text = try decode(data: data)
        let rows = parseRows(text)
        guard let headers = rows.first else { throw CashRunwayError.validation(L10n.string("CSV file is empty.")) }
        let headerIndex = Dictionary(uniqueKeysWithValues: headers.enumerated().map { ($1, $0) })
        let preset = detectPreset(headers: headers)
        let sourceName = preset.rawValue
        let isBankPreset = preset == .monobank || preset == .privatBank
        var invalidRows = 0
        var rowErrors: [CSVRowError] = []
        let wallets = try repository.wallets()
        let resolver = try BankCategoryMapper(repository: repository)

        var preparedRows: [PreparedImportRow] = []

        for (offset, row) in rows.dropFirst().enumerated() {
            do {
                let date = try parseDate(from: cell(row, mapping.dateColumn, headerIndex))
                try validateCurrency(row: row, mapping: mapping, headerIndex: headerIndex)
                let signedAmount = try parseAmount(row: row, mapping: mapping, headerIndex: headerIndex)
                let kind = parseKind(row: row, mapping: mapping, headerIndex: headerIndex, signedAmount: signedAmount)
                guard kind != .transfer else {
                    throw CashRunwayError.validation(L10n.string("Transfer rows are not supported for CSV import."))
                }
                guard let walletID = parseWalletID(
                    row: row,
                    mapping: mapping,
                    headerIndex: headerIndex,
                    wallets: wallets
                ) else {
                    throw CashRunwayError.validation(L10n.string("Wallet ID not found for CSV row."))
                }
                let merchant = cell(row, mapping.merchantColumn, headerIndex)
                let note = cell(row, mapping.noteColumn, headerIndex)
                let rawCategoryName = normalizedCategoryName(cell(row, mapping.categoryColumn, headerIndex))
                let mcc = parsedMCC(cell(row, mapping.mccColumn, headerIndex))
                let rawLabels = rawLabelNames(from: cell(row, mapping.labelsColumn, headerIndex))
                let currency = normalizedCurrency(cell(row, mapping.currencyColumn, headerIndex))

                let resolutionSource: BankCategoryResolutionSource = isBankPreset
                    ? .bankStatement(preset == .monobank ? .monobank : .privatBank)
                    : .cashRunwayWallet
                let resolvedCategory = resolver.resolve(
                    source: resolutionSource,
                    kind: kind,
                    merchant: merchant,
                    description: merchant,
                    rawCategoryName: rawCategoryName,
                    mcc: mcc,
                    originalMcc: nil
                )
                let resolvedCategoryName = resolvedCategory?.categoryName ?? rawCategoryName
                let appearance = resolvedCategoryName.flatMap { importedCategoryAppearance(for: $0, kind: kind) }

                let fingerprint = importFingerprint(
                    .init(
                        sourceName: sourceName,
                        walletID: walletID,
                        kind: kind,
                        occurredAt: date,
                        amountMinor: abs(signedAmount),
                        merchant: merchant,
                        note: note,
                        categoryName: resolvedCategoryName,
                        currency: currency
                    )
                )
                let draft = TransactionDraft(
                    kind: kind,
                    walletID: walletID,
                    amountMinor: abs(signedAmount),
                    occurredAt: date,
                    merchant: merchant,
                    note: note,
                    source: .importCSV
                )
                preparedRows.append(
                    PreparedImportRow(
                        rowNumber: offset + 2,
                        draft: draft,
                        fingerprint: fingerprint,
                        sourceName: sourceName,
                        rawCategoryName: resolvedCategoryName,
                        rawLabelNames: rawLabels,
                        currency: currency,
                        categoryIconName: appearance?.iconName,
                        categoryColorHex: appearance?.colorHex,
                        categoryID: resolvedCategory?.categoryID
                    )
                )
            } catch {
                invalidRows += 1
                if rowErrors.count < 20 {
                    rowErrors.append(CSVRowError(rowNumber: offset + 2, message: error.localizedDescription))
                }
            }
        }

        return try repository.commitCSVImport(
            fileName: fileName,
            sourceName: sourceName,
            preparedRows: preparedRows,
            rowErrors: rowErrors,
            invalidRows: invalidRows
        )
    }

    public func defaultMapping(headers: [String], preset: CSVPreset, walletID: UUID?) -> CSVImportMapping {
        let dateColumn = header(
            named: ["Дата і час операції", "Дата i час операції", "Дата операції", "Дата", "Date and time", "Date", "date"],
            in: headers
        ) ?? headers.first ?? ""
        let amountColumn = header(named: ["Сума в грн", "Amount", "amount", "sum"], in: headers)
            ?? header(matchingPrefix: ["Сума в валюті картки", "Card currency amount"], in: headers)
        let debitColumn = header(named: ["Debit", "debit", "Витрати"], in: headers)
        let creditColumn = header(named: ["Credit", "credit", "Надходження"], in: headers)
        let typeColumn = header(named: ["Type", "type"], in: headers)
        let walletColumn = header(named: ["Wallet", "wallet"], in: headers)
        let isSignedAmount = amountColumn.map {
            $0.range(of: "валюті картки", options: [.caseInsensitive, .diacriticInsensitive]) != nil
                || $0.range(of: "card currency amount", options: [.caseInsensitive, .diacriticInsensitive]) != nil
        } ?? false
        let currencyColumn: String? = (preset == .monobank || (preset == .privatBank && isSignedAmount))
            ? nil
            : header(named: ["Currency", "currency", "Валюта", "Валюта картки"], in: headers)
        let merchantColumn = header(
            named: ["Деталі операції", "Опис операції", "Description", "description", "Merchant", "merchant", "Призначення"],
            in: headers
        )
        let noteColumn = header(named: ["Comment", "comment", "Note", "note"], in: headers)
        let categoryColumn = header(named: ["Категорія", "Category", "category", "Category name", "category name"], in: headers)
        let mccColumn = header(named: ["MCC", "mcc"], in: headers)
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
            defaultKind: (preset == .monobank || (preset == .privatBank && isSignedAmount)) ? .income : .expense,
            typeColumn: typeColumn,
            walletColumn: walletColumn,
            currencyColumn: currencyColumn,
            authorColumn: authorColumn,
            mccColumn: mccColumn
        )
    }

    public func exportCSV(query: TransactionQuery = .init()) throws -> String {
        var exportQuery = query
        exportQuery.kinds = query.kinds.subtracting([.transfer])
        let header = [
            "Date",
            "Wallet",
            "Type",
            "Category name",
            "Merchant",
            "Amount",
            "Currency",
            "Note",
            "Labels",
            "Author"
        ]
        guard !exportQuery.kinds.isEmpty else {
            return header.joined(separator: ",")
        }
        let transactions = try repository.transactions(query: exportQuery, limit: nil)
        let dateFormatter = ISO8601DateFormatter()
        let lines = transactions.map { item in
            [
                dateFormatter.string(from: item.occurredAt),
                item.walletName,
                item.kind.rawValue.capitalized,
                item.categoryName ?? "",
                item.merchant,
                MoneyFormatter.plainString(from: item.amountMinor),
                "UAH",
                item.note,
                item.labels.map(\.name).joined(separator: "|"),
                ""
            ].map(escape).joined(separator: ",")
        }
        return ([header.joined(separator: ",")] + lines).joined(separator: "\n")
    }

    private func decode(data: Data) throws -> String {
        if let utf8 = String(data: data, encoding: .utf8) {
            return utf8
        }
        let cfEncoding = CFStringConvertEncodingToNSStringEncoding(
            CFStringEncoding(CFStringEncodings.windowsCyrillic.rawValue)
        )
        if let cp1251 = String(data: data, encoding: String.Encoding(rawValue: cfEncoding)) {
            return cp1251
        }
        throw CashRunwayError.validation(L10n.string("Unsupported CSV encoding."))
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
        let ukrainianTimeFormatter = DateFormatter()
        ukrainianTimeFormatter.locale = Locale(identifier: "uk_UA")
        ukrainianTimeFormatter.timeZone = TimeZone(identifier: "Europe/Kyiv")
        ukrainianTimeFormatter.dateFormat = "dd.MM.yyyy HH:mm:ss"
        if let date = ukrainianTimeFormatter.date(from: input) {
            return date
        }
        let ukrainianDateFormatter = DateFormatter()
        ukrainianDateFormatter.locale = Locale(identifier: "uk_UA")
        ukrainianDateFormatter.dateFormat = "dd.MM.yyyy"
        if let date = ukrainianDateFormatter.date(from: input) {
            return date
        }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        if let date = formatter.date(from: input) {
            return date
        }
        throw CashRunwayError.validation(L10n.string("Unsupported date format."))
    }

    private func parseAmount(row: [String], mapping: CSVImportMapping, headerIndex: [String: Int]) throws -> Int64 {
        if let amountColumn = mapping.amountColumn {
            return try MoneyFormatter.parseMinorUnits(cell(row, amountColumn, headerIndex))
        }
        let debit = try? MoneyFormatter.parseMinorUnits(cell(row, mapping.debitColumn, headerIndex))
        let credit = try? MoneyFormatter.parseMinorUnits(cell(row, mapping.creditColumn, headerIndex))
        if let debit, debit != 0 { return -abs(debit) }
        if let credit, credit != 0 { return abs(credit) }
        throw CashRunwayError.validation(L10n.string("Could not parse amount."))
    }

    private func parseKind(
        row: [String],
        mapping: CSVImportMapping,
        headerIndex: [String: Int],
        signedAmount: Int64
    ) -> TransactionDraft.Kind {
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

    private func parseWalletID(
        row: [String],
        mapping: CSVImportMapping,
        headerIndex: [String: Int],
        wallets: [Wallet]
    ) -> UUID? {
        let raw = cell(row, mapping.walletColumn, headerIndex)
        guard !raw.isEmpty else { return mapping.walletID }
        return wallets.first(where: { $0.name.caseInsensitiveCompare(raw) == .orderedSame })?.id ?? mapping.walletID
    }

    private func validateCurrency(row: [String], mapping: CSVImportMapping, headerIndex: [String: Int]) throws {
        let raw = cell(row, mapping.currencyColumn, headerIndex)
        guard !raw.isEmpty else { return }
        let normalized = raw.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard normalized == "UAH" || normalized == "₴" || normalized == "ГРН" else {
            throw CashRunwayError.validation(L10n.string("Unsupported currency."))
        }
    }

    private func parsedMCC(_ raw: String) -> Int? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        if let intValue = Int(trimmed), intValue > 0 {
            return intValue
        }
        let withoutDecimalZeros = trimmed.replacingOccurrences(of: "\\.0+$", with: "", options: .regularExpression)
        if let intValue = Int(withoutDecimalZeros), intValue > 0 {
            return intValue
        }
        return nil
    }

    private func importedCategoryAppearance(
        for name: String,
        kind: TransactionDraft.Kind
    ) -> ImportedCategoryAppearance? {
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

    private func normalizedCurrency(_ input: String) -> String? {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private func rawLabelNames(from raw: String) -> [String] {
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
        return names.filter { !$0.isEmpty }
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
        .init(
            keywords: [
                "relationship",
                "dating",
                "romance",
                "love",
                "отношен",
                "стосунк",
                "кохан"
            ],
            iconName: "heart.fill",
            colorHex: "#FF5E57"
        ),
        .init(
            keywords: [
                "grocer",
                "product",
                "supermarket",
                "продукт",
                "супермаркет"
            ],
            iconName: "basket.fill",
            colorHex: "#21C596"
        ),
        .init(
            keywords: [
                "food",
                "drink",
                "еда",
                "їжа",
                "харч",
                "напит",
                "напій"
            ],
            iconName: "fork.knife",
            colorHex: "#B58B4A"
        ),
        .init(
            keywords: [
                "restaurant",
                "cafe",
                "coffee",
                "ресторан",
                "кафе",
                "кофе",
                "кава"
            ],
            iconName: "fork.knife",
            colorHex: "#5CCDC8"
        ),
        .init(
            keywords: [
                "transport",
                "taxi",
                "metro",
                "bus",
                "tram",
                "транспорт",
                "такси",
                "таксі",
                "метро",
                "автобус",
                "проезд",
                "проїзд"
            ],
            iconName: "tram.fill",
            colorHex: "#FFC400"
        ),
        .init(
            keywords: [
                "rent",
                "housing",
                "home",
                "apartment",
                "аренд",
                "оренд",
                "жиль",
                "житл",
                "квартир"
            ],
            iconName: "house.fill",
            colorHex: "#E5862F"
        ),
        .init(
            keywords: [
                "bill",
                "utilit",
                "electric",
                "water",
                "gas",
                "internet",
                "счет",
                "счёт",
                "рахунк",
                "коммун",
                "комун",
                "свет",
                "світло",
                "вода",
                "газ",
                "інтернет"
            ],
            iconName: "bolt.fill",
            colorHex: "#6FD03B"
        ),
        .init(
            keywords: [
                "health",
                "doctor",
                "pharmacy",
                "clinic",
                "мед",
                "врач",
                "лікар",
                "аптек",
                "здоров"
            ],
            iconName: "cross.case.fill",
            colorHex: "#E96176"
        ),
        .init(
            keywords: [
                "shopping",
                "clothes",
                "market",
                "покуп",
                "магазин",
                "одеж",
                "одяг"
            ],
            iconName: "bag.fill",
            colorHex: "#5FD4BF"
        ),
        .init(
            keywords: [
                "entertain",
                "movie",
                "cinema",
                "game",
                "развлеч",
                "кіно",
                "кино",
                "ігри",
                "игры"
            ],
            iconName: "theatermasks.fill",
            colorHex: "#FFA600"
        ),
        .init(
            keywords: [
                "education",
                "school",
                "course",
                "book",
                "обуч",
                "образов",
                "освіт",
                "навчан",
                "курс",
                "книг"
            ],
            iconName: "book.closed.fill",
            colorHex: "#4D86C6"
        ),
        .init(
            keywords: [
                "travel",
                "flight",
                "hotel",
                "trip",
                "поезд",
                "подорож",
                "путеше",
                "отель",
                "готел",
                "авиа",
                "авіа"
            ],
            iconName: "airplane",
            colorHex: "#E85D8E"
        ),
        .init(
            keywords: [
                "gift",
                "present",
                "подар"
            ],
            iconName: "gift.fill",
            colorHex: "#FF5E57"
        ),
        .init(
            keywords: [
                "pet",
                "cat",
                "dog",
                "animal",
                "питом",
                "живот",
                "тварин",
                "кіт",
                "кот",
                "собак"
            ],
            iconName: "pawprint.fill",
            colorHex: "#B78B4A"
        )
    ]

    private static let incomeAppearanceRules: [ImportedCategoryAppearanceRule] = [
        .init(
            keywords: [
                "salary",
                "wage",
                "payroll",
                "зарплат",
                "заробіт",
                "заробот"
            ],
            iconName: "briefcase.fill",
            colorHex: "#2AAAD2"
        ),
        .init(
            keywords: [
                "bonus",
                "бонус",
                "прем"
            ],
            iconName: "crown.fill",
            colorHex: "#F7A72A"
        ),
        .init(
            keywords: [
                "gift",
                "present",
                "подар"
            ],
            iconName: "gift.fill",
            colorHex: "#FF5E57"
        ),
        .init(
            keywords: [
                "refund",
                "cashback",
                "reimbursement",
                "возврат",
                "поверн",
                "кешбек"
            ],
            iconName: "arrow.uturn.backward.circle.fill",
            colorHex: "#16C790"
        ),
        .init(
            keywords: [
                "freelance",
                "project",
                "side",
                "contract",
                "фриланс",
                "проект",
                "контракт"
            ],
            iconName: "briefcase.fill",
            colorHex: "#2AAAD2"
        )
    ]

    private func header(named candidates: [String], in headers: [String]) -> String? {
        headers.first { header in
            candidates.contains { $0.caseInsensitiveCompare(header) == .orderedSame }
        }
    }

    private func header(matchingPrefix prefixes: [String], in headers: [String]) -> String? {
        headers.first { header in
            prefixes.contains { prefix in
                header.range(of: prefix, options: [.caseInsensitive, .diacriticInsensitive]) != nil
            }
        }
    }

    private func escape(_ value: String) -> String {
        let escaped = value.replacingOccurrences(of: "\"", with: "\"\"")
        return "\"\(escaped)\""
    }
}
