import Foundation

/// A minimal, explicitly redacted snapshot of a bank statement import.
///
/// This is the only payload ever stored in `bank_transaction_imports.raw_json`.
/// Sensitive fields such as `counter_iban`, `masked_pan`, `balance`,
/// `counter_name`, `comment`, and `receipt_id` are intentionally excluded.
/// Dedup and linkage rely on normalized columns, not this JSON.
public struct BankTransactionRawAuditPayload: Codable, Hashable, Sendable {
    public static let schemaVersion: Int = 1

    public let schemaVersion: Int
    public let provider: BankProvider
    public let providerAccountID: String
    public let statementItemID: String
    public let statementTime: Int
    public let amountMinorSigned: Int64
    public let currencyCode: Int
    public let mcc: Int?
    public let originalMCC: Int?
    public let redacted: Bool

    public init(
        schemaVersion: Int = Self.schemaVersion,
        provider: BankProvider,
        providerAccountID: String,
        statementItemID: String,
        statementTime: Int,
        amountMinorSigned: Int64,
        currencyCode: Int,
        mcc: Int?,
        originalMCC: Int?,
        redacted: Bool = true
    ) {
        self.schemaVersion = schemaVersion
        self.provider = provider
        self.providerAccountID = providerAccountID
        self.statementItemID = statementItemID
        self.statementTime = statementTime
        self.amountMinorSigned = amountMinorSigned
        self.currencyCode = currencyCode
        self.mcc = mcc
        self.originalMCC = originalMCC
        self.redacted = redacted
    }

    public init(from item: MonobankStatementItem, provider: BankProvider, providerAccountID: String) {
        self.init(
            provider: provider,
            providerAccountID: providerAccountID,
            statementItemID: item.id,
            statementTime: item.time,
            amountMinorSigned: item.amount,
            currencyCode: item.currencyCode,
            mcc: item.mcc,
            originalMCC: item.originalMcc,
            redacted: true
        )
    }
}
