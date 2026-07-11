import Foundation
import GRDB
import CryptoKit

public enum CSVPreset: String, CaseIterable, Sendable {
    case cashRunwayWallet = "Cash Runway Wallet"
    case privatBank = "PrivatBank"
    case monobank = "Monobank"
    case generic = "Generic CSV"
}

public enum CSVImportRowFilter: Equatable, Sendable {
    case allTransactions
    case expensesOnly

    fileprivate func includes(_ kind: TransactionDraft.Kind) -> Bool {
        switch self {
        case .allTransactions:
            true
        case .expensesOnly:
            kind == .expense
        }
    }
}

public enum CSVCategoryMappingDisplayMode: Equatable, Sendable {
    case autoBankRules
    case sourceColumn(String?)
}

public enum StatementFileKind: String, Codable, Hashable, Sendable {
    case csv
    case xlsx
}

public enum BankStatementFormatRole: Hashable, Sendable {
    case cashRunwayExport
    case bankStatement(BankProvider?)
    case genericBankStatement
}

public struct BankStatementFormat: Hashable, Sendable {
    public let id: String
    public let displayName: String
    public let fileKind: StatementFileKind
    public let role: BankStatementFormatRole

    public static let cashRunwayCSV = BankStatementFormat(
        id: "cash-runway.csv.v1",
        displayName: "Cash Runway Wallet CSV",
        fileKind: .csv,
        role: .cashRunwayExport
    )

    public static let monobankCSVv1 = BankStatementFormat(
        id: "monobank.csv.v1",
        displayName: "Monobank CSV",
        fileKind: .csv,
        role: .bankStatement(.monobank)
    )

    public static let privatBankCSVv1 = BankStatementFormat(
        id: "privatbank.csv.v1",
        displayName: "PrivatBank CSV",
        fileKind: .csv,
        role: .bankStatement(.privatBank)
    )

    public static let privatBankXLSXv1 = BankStatementFormat(
        id: "privatbank.xlsx.v1",
        displayName: "PrivatBank XLSX",
        fileKind: .xlsx,
        role: .bankStatement(.privatBank)
    )

    public static let genericBankCSV = BankStatementFormat(
        id: "generic-bank.csv.v1",
        displayName: "Generic Bank CSV",
        fileKind: .csv,
        role: .genericBankStatement
    )

    public static let genericBankXLSX = BankStatementFormat(
        id: "generic-bank.xlsx.v1",
        displayName: "Generic Bank XLSX",
        fileKind: .xlsx,
        role: .genericBankStatement
    )
}

public extension CSVImportMapping {
    func categoryMappingDisplayMode(for preset: CSVPreset) -> CSVCategoryMappingDisplayMode {
        if categoryColumn == nil, preset == .monobank || preset == .privatBank {
            return .autoBankRules
        }
        return .sourceColumn(categoryColumn)
    }

    func categoryMappingDisplayMode(for format: BankStatementFormat) -> CSVCategoryMappingDisplayMode {
        if categoryColumn == nil {
            switch format.role {
            case .bankStatement:
                return .autoBankRules
            case .cashRunwayExport, .genericBankStatement:
                break
            }
        }
        return .sourceColumn(categoryColumn)
    }
}

private struct BankStatementDefaultMapping: Sendable {
    var dateColumns: [String] = []
    var amountColumns: [String] = []
    var amountPrefixes: [String] = []
    var debitColumns: [String] = ["Debit", "debit", "Витрати"]
    var creditColumns: [String] = ["Credit", "credit", "Надходження"]
    var merchantColumns: [String] = []
    var noteColumns: [String] = []
    var categoryColumns: [String] = []
    var labelsColumns: [String] = []
    var typeColumns: [String] = []
    var walletColumns: [String] = []
    var currencyColumns: [String] = []
    var authorColumns: [String] = []
    var mccColumns: [String] = []
    var defaultKind: TransactionDraft.Kind = .expense
    var omitCurrencyForSignedAmount = false
    var useDebitCreditColumns = false
}

private struct BankStatementFormatDefinition: Sendable {
    let format: BankStatementFormat
    let preset: CSVPreset
    let requiredHeaderGroups: [[String]]
    let minimumConfidence: Int
    let defaultMapping: BankStatementDefaultMapping

    func matchScore(headers: [String]) -> Int {
        let normalizedHeaders = Set(headers.map(normalizedCSVHeader))
        var score = 0
        for group in requiredHeaderGroups {
            let matched = group.contains { normalizedHeaders.contains(normalizedCSVHeader($0)) }
            guard matched else { return 0 }
            score += 1
        }
        return score >= minimumConfidence ? score : 0
    }
}

private func normalizedCSVHeader(_ header: String) -> String {
    header
        .replacingOccurrences(of: "\u{feff}", with: "")
        .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "uk_UA"))
        .lowercased()
        .filter { $0.isLetter || $0.isNumber }
}

private struct ImportFingerprintInput {
    let sourceName: String
    let walletID: UUID
    let kind: TransactionDraft.Kind
    let occurredAt: Date
    let amountMinor: Int64
    let merchant: String?
    let note: String?
    let currency: String?
}

private struct ParsedAmount {
    let signedMinor: Int64
    let inferredKind: TransactionDraft.Kind?
}

private func importFingerprint(_ input: ImportFingerprintInput) -> String {
    let normalizedMerchant = (input.merchant ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    let normalizedNote = (input.note ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
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
        normalizedCurrency
    ]
    let input = components.joined(separator: "|")
    let hash = SHA256.hash(data: Data(input.utf8))
    return hash.compactMap { String(format: "%02x", $0) }.joined()
}

// CSV import/export intentionally keeps its parser and category heuristics together.
// swiftlint:disable:next type_body_length
public final class CSVService: CSVImportServicing, @unchecked Sendable {
    // @unchecked Sendable is justified: `repository` is Sendable (GRDB
    // DatabaseQueue serialization); `formatDefinitions` is an immutable `let`
    // array of value types.
    private let repository: CashRunwayRepository
    private let formatDefinitions: [BankStatementFormatDefinition]

    public init(repository: CashRunwayRepository) {
        self.repository = repository
        self.formatDefinitions = CSVService.defaultFormatDefinitions
    }

    private static let defaultFormatDefinitions: [BankStatementFormatDefinition] = [
        BankStatementFormatDefinition(
            format: .cashRunwayCSV,
            preset: .cashRunwayWallet,
            requiredHeaderGroups: [
                ["Date"],
                ["Wallet"],
                ["Type"],
                ["Category name"],
                ["Amount"],
                ["Currency"],
                ["Note"],
                ["Labels"],
                ["Author"],
            ],
            minimumConfidence: 9,
            defaultMapping: BankStatementDefaultMapping(
                dateColumns: ["Date"],
                amountColumns: ["Amount"],
                merchantColumns: ["Merchant"],
                noteColumns: ["Note"],
                categoryColumns: ["Category name"],
                labelsColumns: ["Labels"],
                typeColumns: ["Type"],
                walletColumns: ["Wallet"],
                currencyColumns: ["Currency"],
                authorColumns: ["Author"]
            )
        ),
        BankStatementFormatDefinition(
            format: .monobankCSVv1,
            preset: .monobank,
            requiredHeaderGroups: [
                ["Дата і час операції", "Дата i час операції", "Date and time"],
                ["Деталі операції", "Description"],
                ["MCC"],
                ["Сума (UAH)", "Сума в валюті картки (UAH)", "Сума в валюті картки", "Card currency amount, (UAH)", "Card currency amount"],
            ],
            minimumConfidence: 4,
            defaultMapping: BankStatementDefaultMapping(
                dateColumns: ["Дата і час операції", "Дата i час операції", "Date and time", "Date"],
                amountColumns: ["Сума (UAH)", "Сума в валюті картки (UAH)", "Card currency amount, (UAH)", "Amount", "amount", "sum"],
                amountPrefixes: ["Сума в валюті картки", "Card currency amount"],
                merchantColumns: ["Деталі операції", "Description", "description", "Merchant", "merchant"],
                noteColumns: ["Comment", "comment", "Note", "note"],
                categoryColumns: ["Категорія", "Category", "category"],
                labelsColumns: ["Labels", "labels", "Tags"],
                typeColumns: ["Type", "type"],
                currencyColumns: ["Currency", "currency", "Валюта", "Валюта картки"],
                mccColumns: ["MCC", "mcc"],
                defaultKind: .income,
                omitCurrencyForSignedAmount: true
            )
        ),
        BankStatementFormatDefinition(
            format: .privatBankCSVv1,
            preset: .privatBank,
            requiredHeaderGroups: [
                ["Дата операції", "Дата"],
                ["Опис операції", "Призначення"],
                ["Сума в грн", "Сума в валюті картки"],
            ],
            minimumConfidence: 3,
            defaultMapping: BankStatementDefaultMapping(
                dateColumns: ["Дата операції", "Дата", "Date"],
                amountColumns: ["Сума в грн", "Amount", "amount", "sum"],
                amountPrefixes: ["Сума в валюті картки", "Card currency amount"],
                merchantColumns: ["Опис операції", "Призначення", "Description", "description", "Merchant", "merchant", "Details"],
                noteColumns: ["Коментар", "Comment", "comment", "Note", "note"],
                categoryColumns: ["Категорія", "Category", "category"],
                labelsColumns: ["Labels", "labels", "Tags"],
                typeColumns: ["Type", "type"],
                walletColumns: ["Wallet", "wallet"],
                currencyColumns: ["Currency", "currency", "Валюта", "Валюта картки"],
                authorColumns: ["Author", "author"],
                mccColumns: ["MCC", "mcc"],
                defaultKind: .expense,
                omitCurrencyForSignedAmount: true
            )
        ),
        BankStatementFormatDefinition(
            format: .privatBankXLSXv1,
            preset: .privatBank,
            requiredHeaderGroups: [
                ["Дата операції", "Дата"],
                ["Опис операції", "Призначення"],
                ["Сума в грн", "Сума в валюті картки"],
            ],
            minimumConfidence: 3,
            defaultMapping: BankStatementDefaultMapping(
                dateColumns: ["Дата операції", "Дата", "Date"],
                amountColumns: ["Сума в грн", "Amount", "amount", "sum"],
                amountPrefixes: ["Сума в валюті картки", "Card currency amount"],
                merchantColumns: ["Опис операції", "Призначення", "Description", "description", "Merchant", "merchant", "Details"],
                noteColumns: ["Коментар", "Comment", "comment", "Note", "note"],
                categoryColumns: ["Категорія", "Category", "category"],
                labelsColumns: ["Labels", "labels", "Tags"],
                typeColumns: ["Type", "type"],
                walletColumns: ["Wallet", "wallet"],
                currencyColumns: ["Currency", "currency", "Валюта", "Валюта картки"],
                authorColumns: ["Author", "author"],
                mccColumns: ["MCC", "mcc"],
                defaultKind: .expense,
                omitCurrencyForSignedAmount: true
            )
        ),
        BankStatementFormatDefinition(
            format: .genericBankCSV,
            preset: .generic,
            requiredHeaderGroups: [],
            minimumConfidence: 0,
            defaultMapping: BankStatementDefaultMapping(
                dateColumns: ["Дата і час операції", "Дата i час операції", "Дата операції", "Дата", "Date and time", "Date", "date"],
                amountColumns: ["Сума в грн", "Amount", "amount", "sum"],
                amountPrefixes: ["Сума в валюті картки", "Card currency amount"],
                merchantColumns: ["Деталі операції", "Опис операції", "Description", "description", "Merchant", "merchant", "Призначення"],
                noteColumns: ["Comment", "comment", "Note", "note"],
                categoryColumns: ["Категорія", "Category", "category", "Category name", "category name"],
                labelsColumns: ["Labels", "labels", "Tags"],
                typeColumns: ["Type", "type"],
                walletColumns: ["Wallet", "wallet"],
                currencyColumns: ["Currency", "currency", "Валюта", "Валюта картки"],
                authorColumns: ["Author", "author"],
                mccColumns: ["MCC", "mcc"],
                useDebitCreditColumns: true
            )
        ),
        BankStatementFormatDefinition(
            format: .genericBankXLSX,
            preset: .generic,
            requiredHeaderGroups: [],
            minimumConfidence: 0,
            defaultMapping: BankStatementDefaultMapping(
                dateColumns: ["Дата і час операції", "Дата i час операції", "Дата операції", "Дата", "Date and time", "Date", "date"],
                amountColumns: ["Сума в грн", "Amount", "amount", "sum"],
                amountPrefixes: ["Сума в валюті картки", "Card currency amount"],
                merchantColumns: ["Деталі операції", "Опис операції", "Description", "description", "Merchant", "merchant", "Призначення"],
                noteColumns: ["Comment", "comment", "Note", "note"],
                categoryColumns: ["Категорія", "Category", "category", "Category name", "category name"],
                labelsColumns: ["Labels", "labels", "Tags"],
                typeColumns: ["Type", "type"],
                walletColumns: ["Wallet", "wallet"],
                currencyColumns: ["Currency", "currency", "Валюта", "Валюта картки"],
                authorColumns: ["Author", "author"],
                mccColumns: ["MCC", "mcc"],
                useDebitCreditColumns: true
            )
        ),
    ]

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
        definition(for: detectFormat(headers: headers))?.preset ?? .generic
    }

    public func detectFormat(headers: [String], fileKind: StatementFileKind = .csv) -> BankStatementFormat {
        let fallback = genericFormat(for: fileKind)
        let candidates = formatDefinitions.filter {
            $0.format.fileKind == fileKind && $0.format != fallback
        }
        let scored = candidates.map { (definition: $0, score: $0.matchScore(headers: headers)) }
        let bestScore = scored.map(\.score).max() ?? 0
        guard bestScore > 0 else { return fallback }
        let winners = scored.filter { $0.score == bestScore }
        return winners.count == 1 ? winners[0].definition.format : fallback
    }

    public func previewPreparedRows(data: Data, mapping: CSVImportMapping, rowFilter: CSVImportRowFilter = .allTransactions, limit: Int = 3) throws -> [PreparedImportRow] {
        let text = try decode(data: data)
        let rows = parseRows(text)
        guard let headers = rows.first else { throw CashRunwayError.validation(L10n.string("CSV file is empty.")) }
        let format = detectFormat(headers: headers)
        return try previewPreparedRows(data: data, format: format, mapping: mapping, rowFilter: rowFilter, limit: limit)
    }

    public func previewPreparedRows(
        data: Data,
        format: BankStatementFormat,
        mapping: CSVImportMapping,
        rowFilter: CSVImportRowFilter = .allTransactions,
        limit: Int = 3
    ) throws -> [PreparedImportRow] {
        guard limit > 0 else { return [] }

        let text = try decode(data: data)
        let rows = parseRows(text)
        guard let headers = rows.first else { throw CashRunwayError.validation(L10n.string("CSV file is empty.")) }
        let headerIndex = Dictionary(uniqueKeysWithValues: headers.enumerated().map { ($1, $0) })
        let sourceName = format.displayName
        let fingerprintSourceName = fingerprintNamespace(for: format)
        let resolutionSource = categoryResolutionSource(for: format)
        let wallets = try repository.wallets()
        let resolver = try BankCategoryMapper(repository: repository)

        var preparedRows: [PreparedImportRow] = []

        for (offset, row) in rows.dropFirst().enumerated() {
            guard preparedRows.count < limit else { break }

            do {
                if let explicitKind = explicitKind(row: row, mapping: mapping, headerIndex: headerIndex),
   !rowFilter.includes(explicitKind) {
    continue
}
let date = try parseDate(from: cell(row, mapping.dateColumn, headerIndex))
let parsedAmount = try parseAmount(row: row, mapping: mapping, headerIndex: headerIndex)
let signedAmount = parsedAmount.signedMinor
let kind = parseKind(
    row: row,
    mapping: mapping,
    headerIndex: headerIndex,
    signedAmount: signedAmount,
    inferredKind: parsedAmount.inferredKind
)
guard rowFilter.includes(kind) else {
    continue
}
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

                guard let wallet = wallets.first(where: { $0.id == walletID }) else {
                    throw CashRunwayError.validation(L10n.string("Wallet not found for CSV row."))
                }
                let walletCurrency = try resolvedWalletCurrency(
                    row: row,
                    mapping: mapping,
                    headerIndex: headerIndex,
                    wallet: wallet
                )
                let fingerprint = importFingerprint(
                        .init(
                            sourceName: fingerprintSourceName,
                            walletID: walletID,
                        kind: kind,
                        occurredAt: date,
                        amountMinor: abs(signedAmount),
                        merchant: merchant,
                        note: note,
                        currency: currency
                    )
                )
                let draft = TransactionDraft(
                    kind: kind,
                    walletID: walletID,
                    amountMinor: abs(signedAmount),
                    currencyCode: walletCurrency,
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
                continue
            }
        }

        return preparedRows
    }

    public func importCSV(
        data: Data,
        fileName: String,
        mapping: CSVImportMapping,
        rowFilter: CSVImportRowFilter = .allTransactions
    ) throws -> CSVImportResult {
        let text = try decode(data: data)
        let rows = parseRows(text)
        guard let headers = rows.first else { throw CashRunwayError.validation(L10n.string("CSV file is empty.")) }
        let format = detectFormat(headers: headers)
        return try importStatement(normalizedData: data, fileName: fileName, format: format, mapping: mapping, rowFilter: rowFilter)
    }

    public func importStatement(
        normalizedData: Data,
        fileName: String,
        format: BankStatementFormat,
        mapping: CSVImportMapping,
        rowFilter: CSVImportRowFilter = .allTransactions
    ) throws -> CSVImportResult {
        let text = try decode(data: normalizedData)
        let rows = parseRows(text)
        guard let headers = rows.first else { throw CashRunwayError.validation(L10n.string("CSV file is empty.")) }
        let headerIndex = Dictionary(uniqueKeysWithValues: headers.enumerated().map { ($1, $0) })
        let sourceName = format.displayName
        let fingerprintSourceName = fingerprintNamespace(for: format)
        let resolutionSource = categoryResolutionSource(for: format)
        var invalidRows = 0
        var rowErrors: [CSVRowError] = []
        let wallets = try repository.wallets()
        let resolver = try BankCategoryMapper(repository: repository)

        var preparedRows: [PreparedImportRow] = []

        for (offset, row) in rows.dropFirst().enumerated() {
do {
    if let explicitKind = explicitKind(row: row, mapping: mapping, headerIndex: headerIndex),
       !rowFilter.includes(explicitKind) {
        continue
    }
    let date = try parseDate(from: cell(row, mapping.dateColumn, headerIndex))
    let parsedAmount = try parseAmount(row: row, mapping: mapping, headerIndex: headerIndex)
    let signedAmount = parsedAmount.signedMinor
    let kind = parseKind(
        row: row,
        mapping: mapping,
        headerIndex: headerIndex,
        signedAmount: signedAmount,
        inferredKind: parsedAmount.inferredKind
    )
    guard rowFilter.includes(kind) else {
        continue
    }
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
                            sourceName: fingerprintSourceName,
                            walletID: walletID,
                        kind: kind,
                        occurredAt: date,
                        amountMinor: abs(signedAmount),
                        merchant: merchant,
                        note: note,
                        currency: currency
                    )
                )
                guard let wallet = wallets.first(where: { $0.id == walletID }) else {
                    throw CashRunwayError.validation(L10n.string("Wallet not found for CSV row."))
                }
                let walletCurrency = try resolvedWalletCurrency(
                    row: row,
                    mapping: mapping,
                    headerIndex: headerIndex,
                    wallet: wallet
                )
                let legacyFingerprint = computeLegacyFingerprint(
                    format: format,
                    fingerprintSourceName: fingerprintSourceName,
                    walletID: walletID,
                    kind: kind,
                    date: date,
                    signedAmount: signedAmount,
                    merchant: merchant,
                    note: note,
                    currency: currency,
                    rawCategoryName: rawCategoryName,
                    hasCurrencyColumn: mapping.currencyColumn != nil
                )
                let draft = TransactionDraft(
                    kind: kind,
                    walletID: walletID,
                    amountMinor: abs(signedAmount),
                    currencyCode: walletCurrency,
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
                        legacyFingerprint: legacyFingerprint,
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
            sourceFormatID: format.id,
            preparedRows: preparedRows,
            rowErrors: rowErrors,
            invalidRows: invalidRows
        )
    }

    private func computeLegacyFingerprint(
        format: BankStatementFormat,
        fingerprintSourceName: String,
        walletID: UUID,
        kind: TransactionDraft.Kind,
        date: Date,
        signedAmount: Int64,
        merchant: String,
        note: String,
        currency: String?,
        rawCategoryName: String?,
        hasCurrencyColumn: Bool
    ) -> String? {
        guard format.role == .genericBankStatement, rawCategoryName == nil else { return nil }
        return importFingerprint(
            .init(
                sourceName: fingerprintSourceName,
                walletID: walletID,
                kind: kind,
                occurredAt: date,
                amountMinor: abs(signedAmount),
                merchant: merchant,
                note: note,
                currency: hasCurrencyColumn ? currency : nil
            )
        )
    }

    public func defaultMapping(headers: [String], format: BankStatementFormat, walletID: UUID?) -> CSVImportMapping {
        let defaults = (
            definition(for: format)
                ?? definition(for: genericFormat(for: format.fileKind))
                ?? definition(for: .genericBankCSV)
        )?.defaultMapping ?? BankStatementDefaultMapping()

        let dateColumn = header(named: defaults.dateColumns, in: headers) ?? headers.first ?? ""
        let amountColumn = header(named: defaults.amountColumns, in: headers)
            ?? header(matchingPrefix: defaults.amountPrefixes, in: headers)
        let debitColumn = header(named: defaults.debitColumns, in: headers)
        let creditColumn = header(named: defaults.creditColumns, in: headers)
        let isSignedAmount = amountColumn.map {
            normalizedCSVHeader($0).contains(normalizedCSVHeader("Сума в валюті картки"))
                || normalizedCSVHeader($0).contains(normalizedCSVHeader("Card currency amount"))
        } ?? false
        let isUAHNormalized = amountColumn.map {
            normalizedCSVHeader($0).contains(normalizedCSVHeader("сума uah"))
                || normalizedCSVHeader($0).contains(normalizedCSVHeader("сума (uah)"))
        } ?? false
        let currencyColumn: String? = defaults.omitCurrencyForSignedAmount && (isSignedAmount || isUAHNormalized)
            ? nil
            : header(named: defaults.currencyColumns, in: headers)
        let effectiveDefaultKind: TransactionDraft.Kind
        let isPrivatBankSignedAmount = format.role == .bankStatement(.privatBank) && isSignedAmount
        if isPrivatBankSignedAmount {
            effectiveDefaultKind = .income
        } else {
            effectiveDefaultKind = defaults.defaultKind
        }
        return CSVImportMapping(
            dateColumn: dateColumn,
            amountColumn: amountColumn,
            debitColumn: defaults.useDebitCreditColumns ? debitColumn : nil,
            creditColumn: defaults.useDebitCreditColumns ? creditColumn : nil,
            merchantColumn: header(named: defaults.merchantColumns, in: headers),
            noteColumn: header(named: defaults.noteColumns, in: headers),
            categoryColumn: header(named: defaults.categoryColumns, in: headers),
            labelsColumn: header(named: defaults.labelsColumns, in: headers),
            walletID: walletID,
            defaultKind: effectiveDefaultKind,
            typeColumn: header(named: defaults.typeColumns, in: headers),
            walletColumn: header(named: defaults.walletColumns, in: headers),
            currencyColumn: currencyColumn,
            authorColumn: header(named: defaults.authorColumns, in: headers),
            mccColumn: header(named: defaults.mccColumns, in: headers)
        )
    }

    public func defaultMapping(headers: [String], preset: CSVPreset, walletID: UUID?) -> CSVImportMapping {
        defaultMapping(headers: headers, format: legacyFormat(for: preset), walletID: walletID)
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
                item.currencyCode.rawValue,
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
        if let iso = ISO8601DateFormatter().date(from: input) {
            return iso
        }
        let isoDateFormatter = ISO8601DateFormatter()
        isoDateFormatter.formatOptions = [.withFullDate]
        if let dateOnly = isoDateFormatter.date(from: input) {
            return dateOnly
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

    private func parseAmount(row: [String], mapping: CSVImportMapping, headerIndex: [String: Int]) throws -> ParsedAmount {
        if let amountColumn = mapping.amountColumn {
            return ParsedAmount(
                signedMinor: try MoneyFormatter.parseMinorUnits(cell(row, amountColumn, headerIndex)),
                inferredKind: nil
            )
        }
        let debit = try? MoneyFormatter.parseMinorUnits(cell(row, mapping.debitColumn, headerIndex))
        let credit = try? MoneyFormatter.parseMinorUnits(cell(row, mapping.creditColumn, headerIndex))
        if let debit, debit != 0 {
            return ParsedAmount(signedMinor: -abs(debit), inferredKind: .expense)
        }
        if let credit, credit != 0 {
            return ParsedAmount(signedMinor: abs(credit), inferredKind: .income)
        }
        throw CashRunwayError.validation(L10n.string("Could not parse amount."))
    }

    private func explicitKind(row: [String], mapping: CSVImportMapping, headerIndex: [String: Int]) -> TransactionDraft.Kind? {
        let raw = cell(row, mapping.typeColumn, headerIndex).lowercased()
        if raw == "income" || raw == "inflow" || raw == "credit" { return .income }
        if raw == "expense" || raw == "outflow" || raw == "debit" { return .expense }
        if raw == "transfer" { return .transfer }
        return nil
    }

    private func parseKind(
        row: [String],
        mapping: CSVImportMapping,
        headerIndex: [String: Int],
        signedAmount: Int64,
        inferredKind: TransactionDraft.Kind?
    ) -> TransactionDraft.Kind {
        if let explicit = explicitKind(row: row, mapping: mapping, headerIndex: headerIndex) {
            return explicit
        }
        if let inferredKind {
            return inferredKind
        }
        if signedAmount < 0 {
            return .expense
        }
        if signedAmount > 0, mapping.typeColumn != nil || (mapping.amountColumn == nil && (mapping.debitColumn != nil || mapping.creditColumn != nil)) {
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

    private func resolvedWalletCurrency(
        row: [String],
        mapping: CSVImportMapping,
        headerIndex: [String: Int],
        wallet: Wallet
    ) throws -> CurrencyCode {
        let raw = cell(row, mapping.currencyColumn, headerIndex)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !raw.isEmpty else {
            return wallet.currencyCode
        }
        let normalized = raw.uppercased()
        let canonical = (normalized == "₴" || normalized == "ГРН" || normalized == "ГРН.") ? "UAH" : normalized
        guard let rowCurrency = CurrencyCode(rawValue: canonical) else {
            throw CashRunwayError.validation(L10n.string("Unsupported currency: \(raw)."))
        }
        guard rowCurrency == wallet.currencyCode else {
            throw CashRunwayError.validation(L10n.string(
                "Row currency \(rowCurrency.rawValue) does not match wallet currency \(wallet.currencyCode.rawValue)."
            ))
        }
        return wallet.currencyCode
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

    private func definition(for format: BankStatementFormat) -> BankStatementFormatDefinition? {
        formatDefinitions.first { $0.format == format }
    }

    private func genericFormat(for fileKind: StatementFileKind) -> BankStatementFormat {
        switch fileKind {
        case .csv:
            .genericBankCSV
        case .xlsx:
            .genericBankXLSX
        }
    }

    private func legacyFormat(for preset: CSVPreset) -> BankStatementFormat {
        switch preset {
        case .cashRunwayWallet:
            .cashRunwayCSV
        case .monobank:
            .monobankCSVv1
        case .privatBank:
            .privatBankCSVv1
        case .generic:
            .genericBankCSV
        }
    }

    private func fingerprintNamespace(for format: BankStatementFormat) -> String {
        switch format.id {
        case BankStatementFormat.cashRunwayCSV.id:
            "Cash Runway Wallet"
        case BankStatementFormat.monobankCSVv1.id:
            "Monobank"
        case BankStatementFormat.privatBankCSVv1.id, BankStatementFormat.privatBankXLSXv1.id:
            "PrivatBank"
        case BankStatementFormat.genericBankCSV.id, BankStatementFormat.genericBankXLSX.id:
            "Generic CSV"
        default:
            format.id
        }
    }

    private func categoryResolutionSource(for format: BankStatementFormat) -> BankCategoryResolutionSource {
        switch format.role {
        case .cashRunwayExport:
            .cashRunwayWallet
        case .bankStatement(.some(let provider)):
            .bankStatement(provider)
        case .bankStatement(.none), .genericBankStatement:
            .genericBankStatement
        }
    }

    private func header(named candidates: [String], in headers: [String]) -> String? {
        let normalizedCandidates = Set(candidates.map(normalizedCSVHeader))
        return headers.first { normalizedCandidates.contains(normalizedCSVHeader($0)) }
    }

    private func header(matchingPrefix prefixes: [String], in headers: [String]) -> String? {
        let normalizedPrefixes = prefixes.map(normalizedCSVHeader)
        return headers.first { header in
            let normalizedHeader = normalizedCSVHeader(header)
            return normalizedPrefixes.contains { normalizedHeader.contains($0) }
        }
    }

    private func escape(_ value: String) -> String {
        let escaped = value.replacingOccurrences(of: "\"", with: "\"\"")
        return "\"\(escaped)\""
    }
}
