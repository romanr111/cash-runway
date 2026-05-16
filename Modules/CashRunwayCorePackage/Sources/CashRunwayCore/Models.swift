import Foundation

public enum WalletKind: String, CaseIterable, Codable, Sendable {
    case cash
    case card
    case account
    case other
}

public enum CategoryKind: String, CaseIterable, Codable, Sendable {
    case expense
    case income
}

public enum TransactionKind: String, CaseIterable, Codable, Sendable {
    case expense
    case income
    case transferOut = "transfer_out"
    case transferIn = "transfer_in"

    public var affectsCategorySpend: Bool {
        self == .expense
    }

    public var walletDeltaSign: Int64 {
        switch self {
        case .expense, .transferOut:
            -1
        case .income, .transferIn:
            1
        }
    }
}

public enum TransactionSource: String, CaseIterable, Codable, Sendable {
    case manual
    case recurring
    case bankSync = "bank_sync"
    case importCSV = "import_csv"
}

public enum BankProvider: String, Codable, Sendable {
    case monobank
}

public enum BankIntegrationStatus: String, Codable, Sendable {
    case active
    case disabled
    case tokenInvalid
    case syncFailed
}

public enum BankTransactionImportStatus: String, Codable, Sendable {
    case imported
    case skipped
    case failed
}

public struct BankIntegration: Identifiable, Codable, Hashable, Sendable {
    public var id: UUID
    public var provider: BankProvider
    public var displayName: String
    public var status: BankIntegrationStatus
    public var syncStartAt: Date
    public var tokenKeychainAccount: String
    public var lastClientInfoSyncAt: Date?
    public var lastSuccessfulSyncAt: Date?
    public var lastSyncError: String?
    public var createdAt: Date
    public var updatedAt: Date

    public init(id: UUID, provider: BankProvider, displayName: String, status: BankIntegrationStatus, syncStartAt: Date, tokenKeychainAccount: String, lastClientInfoSyncAt: Date?, lastSuccessfulSyncAt: Date?, lastSyncError: String?, createdAt: Date, updatedAt: Date) {
        self.id = id
        self.provider = provider
        self.displayName = displayName
        self.status = status
        self.syncStartAt = syncStartAt
        self.tokenKeychainAccount = tokenKeychainAccount
        self.lastClientInfoSyncAt = lastClientInfoSyncAt
        self.lastSuccessfulSyncAt = lastSuccessfulSyncAt
        self.lastSyncError = lastSyncError
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

public struct BankAccount: Identifiable, Codable, Hashable, Sendable {
    public var id: UUID
    public var integrationID: UUID
    public var provider: BankProvider
    public var providerAccountID: String
    public var walletID: UUID
    public var displayName: String
    public var accountType: String?
    public var currencyCode: Int
    public var maskedPAN: String?
    public var iban: String?
    public var isEnabled: Bool
    public var syncStartAt: Date
    public var lastSuccessfulSyncAt: Date?
    public var lastStatementItemTime: Int?
    public var createdAt: Date
    public var updatedAt: Date

    public init(id: UUID, integrationID: UUID, provider: BankProvider, providerAccountID: String, walletID: UUID, displayName: String, accountType: String?, currencyCode: Int, maskedPAN: String?, iban: String?, isEnabled: Bool, syncStartAt: Date, lastSuccessfulSyncAt: Date?, lastStatementItemTime: Int?, createdAt: Date, updatedAt: Date) {
        self.id = id
        self.integrationID = integrationID
        self.provider = provider
        self.providerAccountID = providerAccountID
        self.walletID = walletID
        self.displayName = displayName
        self.accountType = accountType
        self.currencyCode = currencyCode
        self.maskedPAN = maskedPAN
        self.iban = iban
        self.isEnabled = isEnabled
        self.syncStartAt = syncStartAt
        self.lastSuccessfulSyncAt = lastSuccessfulSyncAt
        self.lastStatementItemTime = lastStatementItemTime
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

public struct BankTransactionImport: Identifiable, Codable, Hashable, Sendable {
    public var id: UUID
    public var provider: BankProvider
    public var integrationID: UUID
    public var bankAccountID: UUID
    public var providerAccountID: String
    public var providerStatementItemID: String
    public var statementTime: Int
    public var amountMinorSigned: Int64
    public var operationAmountMinorSigned: Int64?
    public var currencyCode: Int
    public var mcc: Int?
    public var originalMCC: Int?
    public var description: String?
    public var comment: String?
    public var counterName: String?
    public var counterIBAN: String?
    public var receiptID: String?
    public var hold: Bool?
    public var rawJSON: String
    public var cashRunwayTransactionID: UUID?
    public var importStatus: BankTransactionImportStatus
    public var createdAt: Date
    public var updatedAt: Date

    public init(id: UUID, provider: BankProvider, integrationID: UUID, bankAccountID: UUID, providerAccountID: String, providerStatementItemID: String, statementTime: Int, amountMinorSigned: Int64, operationAmountMinorSigned: Int64?, currencyCode: Int, mcc: Int?, originalMCC: Int?, description: String?, comment: String?, counterName: String?, counterIBAN: String?, receiptID: String?, hold: Bool?, rawJSON: String, cashRunwayTransactionID: UUID?, importStatus: BankTransactionImportStatus, createdAt: Date, updatedAt: Date) {
        self.id = id
        self.provider = provider
        self.integrationID = integrationID
        self.bankAccountID = bankAccountID
        self.providerAccountID = providerAccountID
        self.providerStatementItemID = providerStatementItemID
        self.statementTime = statementTime
        self.amountMinorSigned = amountMinorSigned
        self.operationAmountMinorSigned = operationAmountMinorSigned
        self.currencyCode = currencyCode
        self.mcc = mcc
        self.originalMCC = originalMCC
        self.description = description
        self.comment = comment
        self.counterName = counterName
        self.counterIBAN = counterIBAN
        self.receiptID = receiptID
        self.hold = hold
        self.rawJSON = rawJSON
        self.cashRunwayTransactionID = cashRunwayTransactionID
        self.importStatus = importStatus
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

public struct BankCategoryRule: Identifiable, Codable, Hashable, Sendable {
    public var id: UUID
    public var provider: BankProvider
    public var ruleType: String
    public var merchantPattern: String?
    public var mcc: Int?
    public var categoryID: UUID
    public var confidence: Int
    public var createdAt: Date
    public var updatedAt: Date

    public init(id: UUID, provider: BankProvider, ruleType: String, merchantPattern: String?, mcc: Int?, categoryID: UUID, confidence: Int = 100, createdAt: Date, updatedAt: Date) {
        self.id = id
        self.provider = provider
        self.ruleType = ruleType
        self.merchantPattern = merchantPattern
        self.mcc = mcc
        self.categoryID = categoryID
        self.confidence = confidence
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

public struct BankExternalExpenseItem: Codable, Hashable, Sendable {
    public var providerStatementItemID: String
    public var statementTime: Int
    public var amountMinorSigned: Int64
    public var operationAmountMinorSigned: Int64?
    public var currencyCode: Int
    public var mcc: Int?
    public var originalMCC: Int?
    public var description: String?
    public var comment: String?
    public var counterName: String?
    public var counterIBAN: String?
    public var receiptID: String?
    public var hold: Bool?
    public var rawJSON: String

    public init(providerStatementItemID: String, statementTime: Int, amountMinorSigned: Int64, operationAmountMinorSigned: Int64?, currencyCode: Int, mcc: Int?, originalMCC: Int?, description: String?, comment: String?, counterName: String?, counterIBAN: String?, receiptID: String?, hold: Bool?, rawJSON: String) {
        self.providerStatementItemID = providerStatementItemID
        self.statementTime = statementTime
        self.amountMinorSigned = amountMinorSigned
        self.operationAmountMinorSigned = operationAmountMinorSigned
        self.currencyCode = currencyCode
        self.mcc = mcc
        self.originalMCC = originalMCC
        self.description = description
        self.comment = comment
        self.counterName = counterName
        self.counterIBAN = counterIBAN
        self.receiptID = receiptID
        self.hold = hold
        self.rawJSON = rawJSON
    }
}

public struct MonobankStatementItem: Codable, Hashable, Sendable {
    public var id: String
    public var time: Int
    public var description: String
    public var mcc: Int?
    public var originalMcc: Int?
    public var amount: Int64
    public var operationAmount: Int64?
    public var currencyCode: Int
    public var commissionRate: Int64?
    public var cashbackAmount: Int64?
    public var balance: Int64?
    public var hold: Bool?
    public var receiptId: String?
    public var comment: String?
    public var counterEdrpou: String?
    public var counterIban: String?
    public var counterName: String?

    public init(id: String, time: Int, description: String, mcc: Int?, originalMcc: Int?, amount: Int64, operationAmount: Int64?, currencyCode: Int, commissionRate: Int64?, cashbackAmount: Int64?, balance: Int64?, hold: Bool?, receiptId: String?, comment: String?, counterEdrpou: String?, counterIban: String?, counterName: String?) {
        self.id = id
        self.time = time
        self.description = description
        self.mcc = mcc
        self.originalMcc = originalMcc
        self.amount = amount
        self.operationAmount = operationAmount
        self.currencyCode = currencyCode
        self.commissionRate = commissionRate
        self.cashbackAmount = cashbackAmount
        self.balance = balance
        self.hold = hold
        self.receiptId = receiptId
        self.comment = comment
        self.counterEdrpou = counterEdrpou
        self.counterIban = counterIban
        self.counterName = counterName
    }
}

public struct MonobankClientInfo: Decodable, Hashable, Sendable {
    public var name: String
    public var accounts: [MonobankAccount]

    public init(name: String, accounts: [MonobankAccount]) {
        self.name = name
        self.accounts = accounts
    }
}

public struct MonobankAccount: Decodable, Hashable, Sendable {
    public var id: String
    public var type: String?
    public var currencyCode: Int
    public var maskedPan: [String]?
    public var iban: String?

    public init(id: String, type: String?, currencyCode: Int, maskedPan: [String]?, iban: String?) {
        self.id = id
        self.type = type
        self.currencyCode = currencyCode
        self.maskedPan = maskedPan
        self.iban = iban
    }
}

public struct BankSyncImportResult: Codable, Hashable, Sendable {
    public var importedCount: Int
    public var skippedCount: Int

    public init(importedCount: Int = 0, skippedCount: Int = 0) {
        self.importedCount = importedCount
        self.skippedCount = skippedCount
    }
}

public struct BankSyncResult: Codable, Hashable, Sendable {
    public var importedCount: Int
    public var skippedCount: Int
    public var syncedAccountCount: Int

    public init(importedCount: Int = 0, skippedCount: Int = 0, syncedAccountCount: Int = 0) {
        self.importedCount = importedCount
        self.skippedCount = skippedCount
        self.syncedAccountCount = syncedAccountCount
    }
}

public enum BankSyncError: Error, Equatable, LocalizedError, Sendable {
    case tokenInvalid
    case rateLimited
    case transient(String)
    case invalidResponse

    public var errorDescription: String? {
        switch self {
        case .tokenInvalid:
            "Bank token is invalid."
        case .rateLimited:
            "Bank API rate limit reached."
        case let .transient(message):
            message
        case .invalidResponse:
            "Bank API returned an invalid response."
        }
    }
}

public enum RecurringTemplateKind: String, CaseIterable, Codable, Sendable {
    case expense
    case income
    case transfer
}

public enum RecurrenceRuleType: String, CaseIterable, Codable, Sendable {
    case daily
    case weekly
    case monthly
    case yearly
}

public enum RecurringInstanceStatus: String, CaseIterable, Codable, Sendable {
    case scheduled
    case posted
    case skipped
    case postponed
}

public enum ImportJobStatus: String, CaseIterable, Codable, Sendable {
    case created
    case parsed
    case validated
    case committed
    case failed
    case cancelled
}

public enum TimelinePeriod: String, CaseIterable, Sendable {
    case month, year

    public var displayName: String {
        switch self {
        case .month: return "By months"
        case .year: return "By years"
        }
    }
}

public struct Wallet: Identifiable, Codable, Hashable, Sendable {
    public var id: UUID
    public var name: String
    public var kind: WalletKind
    public var colorHex: String?
    public var iconName: String?
    public var startingBalanceMinor: Int64
    public var currentBalanceMinor: Int64
    public var isArchived: Bool
    public var sortOrder: Int
    public var createdAt: Date
    public var updatedAt: Date

    public init(id: UUID, name: String, kind: WalletKind, colorHex: String?, iconName: String?, startingBalanceMinor: Int64, currentBalanceMinor: Int64, isArchived: Bool, sortOrder: Int, createdAt: Date, updatedAt: Date) {
        self.id = id
        self.name = name
        self.kind = kind
        self.colorHex = colorHex
        self.iconName = iconName
        self.startingBalanceMinor = startingBalanceMinor
        self.currentBalanceMinor = currentBalanceMinor
        self.isArchived = isArchived
        self.sortOrder = sortOrder
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

public struct Category: Identifiable, Codable, Hashable, Sendable {
    public var id: UUID
    public var name: String
    public var kind: CategoryKind
    public var iconName: String?
    public var colorHex: String?
    public var parentID: UUID?
    public var isSystem: Bool
    public var isArchived: Bool
    public var sortOrder: Int
    public var createdAt: Date
    public var updatedAt: Date

    public init(id: UUID, name: String, kind: CategoryKind, iconName: String?, colorHex: String?, parentID: UUID?, isSystem: Bool, isArchived: Bool, sortOrder: Int, createdAt: Date, updatedAt: Date) {
        self.id = id
        self.name = name
        self.kind = kind
        self.iconName = iconName
        self.colorHex = colorHex
        self.parentID = parentID
        self.isSystem = isSystem
        self.isArchived = isArchived
        self.sortOrder = sortOrder
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

public struct Label: Identifiable, Codable, Hashable, Sendable {
    public var id: UUID
    public var name: String
    public var colorHex: String?
    public var createdAt: Date
    public var updatedAt: Date

    public init(id: UUID, name: String, colorHex: String?, createdAt: Date, updatedAt: Date) {
        self.id = id
        self.name = name
        self.colorHex = colorHex
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

public struct CashRunwayTransaction: Identifiable, Codable, Hashable, Sendable {
    public var id: UUID
    public var walletID: UUID
    public var type: TransactionKind
    public var linkedTransferID: UUID?
    public var amountMinor: Int64
    public var occurredAt: Date
    public var localDayKey: Int
    public var localMonthKey: Int
    public var categoryID: UUID?
    public var merchant: String?
    public var note: String?
    public var isDeleted: Bool
    public var source: TransactionSource
    public var recurringTemplateID: UUID?
    public var recurringInstanceID: UUID?
    public var importJobID: UUID?
    public var importFingerprint: String?
    public var createdAt: Date
    public var updatedAt: Date

    public init(id: UUID, walletID: UUID, type: TransactionKind, linkedTransferID: UUID?, amountMinor: Int64, occurredAt: Date, localDayKey: Int, localMonthKey: Int, categoryID: UUID?, merchant: String?, note: String?, isDeleted: Bool, source: TransactionSource, recurringTemplateID: UUID?, recurringInstanceID: UUID?, importJobID: UUID? = nil, importFingerprint: String? = nil, createdAt: Date, updatedAt: Date) {
        self.id = id
        self.walletID = walletID
        self.type = type
        self.linkedTransferID = linkedTransferID
        self.amountMinor = amountMinor
        self.occurredAt = occurredAt
        self.localDayKey = localDayKey
        self.localMonthKey = localMonthKey
        self.categoryID = categoryID
        self.merchant = merchant
        self.note = note
        self.isDeleted = isDeleted
        self.source = source
        self.recurringTemplateID = recurringTemplateID
        self.recurringInstanceID = recurringInstanceID
        self.importJobID = importJobID
        self.importFingerprint = importFingerprint
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

// DEPRECATED — Budgets feature is de-prioritized. Work stopped; do not modify or add tests until resumed.
public struct Budget: Identifiable, Codable, Hashable, Sendable {
    public var id: UUID
    public var categoryID: UUID
    public var monthKey: Int
    public var limitMinor: Int64
    public var isArchived: Bool
    public var createdAt: Date
    public var updatedAt: Date

    public init(id: UUID, categoryID: UUID, monthKey: Int, limitMinor: Int64, isArchived: Bool, createdAt: Date, updatedAt: Date) {
        self.id = id
        self.categoryID = categoryID
        self.monthKey = monthKey
        self.limitMinor = limitMinor
        self.isArchived = isArchived
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

public struct RecurringTemplate: Identifiable, Codable, Hashable, Sendable {
    public var id: UUID
    public var kind: RecurringTemplateKind
    public var walletID: UUID
    public var counterpartyWalletID: UUID?
    public var amountMinor: Int64
    public var categoryID: UUID?
    public var merchant: String?
    public var note: String?
    public var ruleType: RecurrenceRuleType
    public var ruleInterval: Int
    public var dayOfMonth: Int?
    public var weekday: Int?
    public var startDate: Date
    public var endDate: Date?
    public var isActive: Bool
    public var createdAt: Date
    public var updatedAt: Date

    public init(id: UUID, kind: RecurringTemplateKind, walletID: UUID, counterpartyWalletID: UUID?, amountMinor: Int64, categoryID: UUID?, merchant: String?, note: String?, ruleType: RecurrenceRuleType, ruleInterval: Int, dayOfMonth: Int?, weekday: Int?, startDate: Date, endDate: Date?, isActive: Bool, createdAt: Date, updatedAt: Date) {
        self.id = id
        self.kind = kind
        self.walletID = walletID
        self.counterpartyWalletID = counterpartyWalletID
        self.amountMinor = amountMinor
        self.categoryID = categoryID
        self.merchant = merchant
        self.note = note
        self.ruleType = ruleType
        self.ruleInterval = ruleInterval
        self.dayOfMonth = dayOfMonth
        self.weekday = weekday
        self.startDate = startDate
        self.endDate = endDate
        self.isActive = isActive
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

public struct RecurringInstance: Identifiable, Codable, Hashable, Sendable {
    public var id: UUID
    public var templateID: UUID
    public var dueDate: Date
    public var dayKey: Int
    public var status: RecurringInstanceStatus
    public var linkedTransactionID: UUID?
    public var overrideAmountMinor: Int64?
    public var overrideCategoryID: UUID?
    public var overrideNote: String?
    public var overrideMerchant: String?
    public var createdAt: Date
    public var updatedAt: Date

    public init(id: UUID, templateID: UUID, dueDate: Date, dayKey: Int, status: RecurringInstanceStatus, linkedTransactionID: UUID?, overrideAmountMinor: Int64?, overrideCategoryID: UUID?, overrideNote: String?, overrideMerchant: String?, createdAt: Date, updatedAt: Date) {
        self.id = id
        self.templateID = templateID
        self.dueDate = dueDate
        self.dayKey = dayKey
        self.status = status
        self.linkedTransactionID = linkedTransactionID
        self.overrideAmountMinor = overrideAmountMinor
        self.overrideCategoryID = overrideCategoryID
        self.overrideNote = overrideNote
        self.overrideMerchant = overrideMerchant
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

public struct ImportJob: Identifiable, Codable, Hashable, Sendable {
    public var id: UUID
    public var sourceName: String
    public var fileName: String
    public var status: ImportJobStatus
    public var totalRows: Int
    public var validRows: Int
    public var invalidRows: Int
    public var duplicateRows: Int
    public var startedAt: Date
    public var finishedAt: Date?
    public var errorSummary: String?
}

public struct CashRunwayBackup: Codable, Sendable {
    public var metadata: CashRunwayBackupMetadata
    public var wallets: [BackupWallet]
    public var categories: [BackupCategory]
    public var labels: [BackupLabel]
    public var transactions: [BackupTransaction]
    public var transactionLabels: [BackupTransactionLabel]
    public var budgets: [BackupBudget]
    public var recurringTemplates: [BackupRecurringTemplate]
    public var recurringInstances: [BackupRecurringInstance]
    public var importJobs: [BackupImportJob]
}

public struct CashRunwayBackupMetadata: Codable, Hashable, Sendable {
    public var format: String
    public var version: Int
    public var createdAt: Date
    public var appVersion: String
    public var currency: String
}

public struct BackupWallet: Identifiable, Codable, Hashable, Sendable {
    public var id: UUID
    public var name: String
    public var kind: WalletKind
    public var colorHex: String?
    public var iconName: String?
    public var startingBalanceMinor: Int64
    public var currentBalanceMinor: Int64
    public var isArchived: Bool
    public var sortOrder: Int
    public var createdAt: Date
    public var updatedAt: Date
}

public struct BackupCategory: Identifiable, Codable, Hashable, Sendable {
    public var id: UUID
    public var name: String
    public var kind: CategoryKind
    public var iconName: String?
    public var colorHex: String?
    public var parentID: UUID?
    public var isSystem: Bool
    public var isArchived: Bool
    public var sortOrder: Int
    public var createdAt: Date
    public var updatedAt: Date
}

public struct BackupLabel: Identifiable, Codable, Hashable, Sendable {
    public var id: UUID
    public var name: String
    public var colorHex: String?
    public var createdAt: Date
    public var updatedAt: Date
}

public struct BackupTransaction: Identifiable, Codable, Hashable, Sendable {
    public var id: UUID
    public var walletID: UUID
    public var type: TransactionKind
    public var linkedTransferID: UUID?
    public var amountMinor: Int64
    public var occurredAt: Date
    public var localDayKey: Int
    public var localMonthKey: Int
    public var categoryID: UUID?
    public var merchant: String?
    public var note: String?
    public var isDeleted: Bool
    public var source: TransactionSource
    public var recurringTemplateID: UUID?
    public var recurringInstanceID: UUID?
    public var importJobID: UUID?
    public var importFingerprint: String?
    public var createdAt: Date
    public var updatedAt: Date
}

public struct BackupTransactionLabel: Codable, Hashable, Sendable {
    public var transactionID: UUID
    public var labelID: UUID
}

public struct BackupBudget: Identifiable, Codable, Hashable, Sendable {
    public var id: UUID
    public var categoryID: UUID
    public var monthKey: Int
    public var limitMinor: Int64
    public var isArchived: Bool
    public var createdAt: Date
    public var updatedAt: Date
}

public struct BackupRecurringTemplate: Identifiable, Codable, Hashable, Sendable {
    public var id: UUID
    public var kind: RecurringTemplateKind
    public var walletID: UUID
    public var counterpartyWalletID: UUID?
    public var amountMinor: Int64
    public var categoryID: UUID?
    public var merchant: String?
    public var note: String?
    public var ruleType: RecurrenceRuleType
    public var ruleInterval: Int
    public var dayOfMonth: Int?
    public var weekday: Int?
    public var startDate: Date
    public var endDate: Date?
    public var isActive: Bool
    public var createdAt: Date
    public var updatedAt: Date
}

public struct BackupRecurringInstance: Identifiable, Codable, Hashable, Sendable {
    public var id: UUID
    public var templateID: UUID
    public var dueDate: Date
    public var dayKey: Int
    public var status: RecurringInstanceStatus
    public var linkedTransactionID: UUID?
    public var overrideAmountMinor: Int64?
    public var overrideCategoryID: UUID?
    public var overrideNote: String?
    public var overrideMerchant: String?
    public var createdAt: Date
    public var updatedAt: Date
}

public struct BackupImportJob: Identifiable, Codable, Hashable, Sendable {
    public var id: UUID
    public var sourceName: String
    public var fileName: String
    public var status: ImportJobStatus
    public var totalRows: Int
    public var validRows: Int
    public var invalidRows: Int
    public var startedAt: Date
    public var finishedAt: Date?
    public var errorSummary: String?
}

public struct BackupValidationSummary: Hashable, Sendable {
    public var createdAt: Date
    public var walletCount: Int
    public var categoryCount: Int
    public var labelCount: Int
    public var transactionCount: Int
    public var recurringTemplateCount: Int

    public init(createdAt: Date, walletCount: Int, categoryCount: Int, labelCount: Int, transactionCount: Int, recurringTemplateCount: Int) {
        self.createdAt = createdAt
        self.walletCount = walletCount
        self.categoryCount = categoryCount
        self.labelCount = labelCount
        self.transactionCount = transactionCount
        self.recurringTemplateCount = recurringTemplateCount
    }
}

public struct BackupRestoreResult: Sendable {
    public var summary: BackupValidationSummary
    public var safetyBackupURL: URL?

    public init(summary: BackupValidationSummary, safetyBackupURL: URL? = nil) {
        self.summary = summary
        self.safetyBackupURL = safetyBackupURL
    }
}

public enum BackupError: LocalizedError, Equatable {
    case unsupportedFormat
    case unsupportedVersion(Int)
    case duplicateID(String)
    case duplicateRelationship(String)
    case brokenReference(String)
    case invalidTransferPair(String)
    case duplicateImportFingerprint(String)

    public var errorDescription: String? {
        switch self {
        case .unsupportedFormat:
            "This is not a Cash Runway backup file."
        case let .unsupportedVersion(version):
            "Backup version \(version) is not supported."
        case let .duplicateID(entity):
            "Backup contains duplicate \(entity) IDs."
        case let .duplicateRelationship(entity):
            "Backup contains duplicate \(entity) relationships."
        case let .brokenReference(message):
            "Backup contains broken references: \(message)"
        case let .invalidTransferPair(message):
            "Backup contains invalid transfer pairs: \(message)"
        case let .duplicateImportFingerprint(fingerprint):
            "Backup contains duplicate import fingerprint: \(fingerprint)"
        }
    }
}

public final class BackupService: @unchecked Sendable {
    private let repository: CashRunwayRepository

    public init(repository: CashRunwayRepository) {
        self.repository = repository
    }

    public func exportFullBackup() throws -> CashRunwayBackup {
        try repository.exportFullBackup()
    }

    public func encode(_ backup: CashRunwayBackup) throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(backup)
    }

    public func decode(data: Data) throws -> CashRunwayBackup {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom(Self.decodeISO8601Date)
        return try decoder.decode(CashRunwayBackup.self, from: data)
    }

    public func validate(_ backup: CashRunwayBackup) throws -> BackupValidationSummary {
        try BackupValidator.validate(backup)
    }

    public func restore(_ backup: CashRunwayBackup) throws -> BackupRestoreResult {
        _ = try validate(backup)
        let safetyBackupURL = try writeSafetyBackup()
        let result = try repository.restoreFullBackup(backup)
        return BackupRestoreResult(summary: result.summary, safetyBackupURL: safetyBackupURL)
    }

    private func writeSafetyBackup() throws -> URL {
        let currentBackup = try exportFullBackup()
        let data = try encode(currentBackup)
        let directoryURL = FileManager.default.temporaryDirectory.appendingPathComponent("CashRunwayBackups", isDirectory: true)
        try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        let url = directoryURL.appendingPathComponent("pre-restore-cash-runway-backup-\(Self.fileTimestamp()).json")
        try data.write(to: url, options: .atomic)
        return url
    }

    private static func fileTimestamp() -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd-HHmmss"
        return formatter.string(from: Date())
    }

    private static func decodeISO8601Date(_ decoder: Decoder) throws -> Date {
        let container = try decoder.singleValueContainer()
        let value = try container.decode(String.self)

        let fractionalFormatter = ISO8601DateFormatter()
        fractionalFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = fractionalFormatter.date(from: value) {
            return date
        }

        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        if let date = formatter.date(from: value) {
            return date
        }

        throw DecodingError.dataCorruptedError(in: container, debugDescription: "Invalid ISO-8601 date: \(value)")
    }
}

enum BackupValidator {
    static func validate(_ backup: CashRunwayBackup) throws -> BackupValidationSummary {
        guard backup.metadata.format == "cash-runway-backup" else {
            throw BackupError.unsupportedFormat
        }
        guard backup.metadata.version == 1 else {
            throw BackupError.unsupportedVersion(backup.metadata.version)
        }

        let walletIDs = try uniqueIDs(backup.wallets.map(\.id), entity: "wallet")
        let categoryIDs = try uniqueIDs(backup.categories.map(\.id), entity: "category")
        let labelIDs = try uniqueIDs(backup.labels.map(\.id), entity: "label")
        let transactionIDs = try uniqueIDs(backup.transactions.map(\.id), entity: "transaction")
        let budgetIDs = try uniqueIDs(backup.budgets.map(\.id), entity: "budget")
        let recurringTemplateIDs = try uniqueIDs(backup.recurringTemplates.map(\.id), entity: "recurring template")
        let recurringInstanceIDs = try uniqueIDs(backup.recurringInstances.map(\.id), entity: "recurring instance")
        _ = try uniqueIDs(backup.importJobs.map(\.id), entity: "import job")

        try validateCategoryParents(backup.categories, categoryIDs: categoryIDs)
        try validateBudgets(backup.budgets, budgetIDs: budgetIDs, categoryIDs: categoryIDs)
        try validateRecurringTemplates(backup.recurringTemplates, walletIDs: walletIDs, categoryIDs: categoryIDs)
        try validateRecurringInstances(backup.recurringInstances, templateIDs: recurringTemplateIDs, transactionIDs: transactionIDs, categoryIDs: categoryIDs)
        try validateTransactions(backup.transactions, transactionIDs: transactionIDs, walletIDs: walletIDs, categoryIDs: categoryIDs, recurringTemplateIDs: recurringTemplateIDs, recurringInstanceIDs: recurringInstanceIDs)
        try validateTransactionLabels(backup.transactionLabels, transactionIDs: transactionIDs, labelIDs: labelIDs)
        try validateImportFingerprints(backup.transactions)
        try validateTransferPairs(backup.transactions)

        return BackupValidationSummary(
            createdAt: backup.metadata.createdAt,
            walletCount: backup.wallets.count,
            categoryCount: backup.categories.count,
            labelCount: backup.labels.count,
            transactionCount: backup.transactions.count,
            recurringTemplateCount: backup.recurringTemplates.count
        )
    }

    private static func uniqueIDs(_ ids: [UUID], entity: String) throws -> Set<UUID> {
        let set = Set(ids)
        if set.count != ids.count {
            throw BackupError.duplicateID(entity)
        }
        return set
    }

    private static func validateCategoryParents(_ categories: [BackupCategory], categoryIDs: Set<UUID>) throws {
        for category in categories {
            if let parentID = category.parentID, !categoryIDs.contains(parentID) {
                throw BackupError.brokenReference("category \(category.id) parent \(parentID)")
            }
        }
    }

    private static func validateBudgets(_ budgets: [BackupBudget], budgetIDs: Set<UUID>, categoryIDs: Set<UUID>) throws {
        for budget in budgets {
            if !categoryIDs.contains(budget.categoryID) {
                throw BackupError.brokenReference("budget \(budget.id) category \(budget.categoryID)")
            }
        }
    }

    private static func validateRecurringTemplates(_ templates: [BackupRecurringTemplate], walletIDs: Set<UUID>, categoryIDs: Set<UUID>) throws {
        for template in templates {
            if !walletIDs.contains(template.walletID) {
                throw BackupError.brokenReference("recurring template \(template.id) wallet \(template.walletID)")
            }
            if let counterpartyWalletID = template.counterpartyWalletID, !walletIDs.contains(counterpartyWalletID) {
                throw BackupError.brokenReference("recurring template \(template.id) counterparty wallet \(counterpartyWalletID)")
            }
            if let categoryID = template.categoryID, !categoryIDs.contains(categoryID) {
                throw BackupError.brokenReference("recurring template \(template.id) category \(categoryID)")
            }
        }
    }

    private static func validateRecurringInstances(_ instances: [BackupRecurringInstance], templateIDs: Set<UUID>, transactionIDs: Set<UUID>, categoryIDs: Set<UUID>) throws {
        for instance in instances {
            if !templateIDs.contains(instance.templateID) {
                throw BackupError.brokenReference("recurring instance \(instance.id) template \(instance.templateID)")
            }
            if let linkedTransactionID = instance.linkedTransactionID, !transactionIDs.contains(linkedTransactionID) {
                throw BackupError.brokenReference("recurring instance \(instance.id) transaction \(linkedTransactionID)")
            }
            if let categoryID = instance.overrideCategoryID, !categoryIDs.contains(categoryID) {
                throw BackupError.brokenReference("recurring instance \(instance.id) override category \(categoryID)")
            }
        }
    }

    private static func validateTransactions(_ transactions: [BackupTransaction], transactionIDs: Set<UUID>, walletIDs: Set<UUID>, categoryIDs: Set<UUID>, recurringTemplateIDs: Set<UUID>, recurringInstanceIDs: Set<UUID>) throws {
        for transaction in transactions {
            if !walletIDs.contains(transaction.walletID) {
                throw BackupError.brokenReference("transaction \(transaction.id) wallet \(transaction.walletID)")
            }
            if let categoryID = transaction.categoryID, !categoryIDs.contains(categoryID) {
                throw BackupError.brokenReference("transaction \(transaction.id) category \(categoryID)")
            }
            if let linkedTransferID = transaction.linkedTransferID, !transactionIDs.contains(linkedTransferID) {
                throw BackupError.brokenReference("transaction \(transaction.id) linked transfer \(linkedTransferID)")
            }
            if let recurringTemplateID = transaction.recurringTemplateID, !recurringTemplateIDs.contains(recurringTemplateID) {
                throw BackupError.brokenReference("transaction \(transaction.id) recurring template \(recurringTemplateID)")
            }
            if let recurringInstanceID = transaction.recurringInstanceID, !recurringInstanceIDs.contains(recurringInstanceID) {
                throw BackupError.brokenReference("transaction \(transaction.id) recurring instance \(recurringInstanceID)")
            }
        }
    }

    private static func validateTransactionLabels(_ rows: [BackupTransactionLabel], transactionIDs: Set<UUID>, labelIDs: Set<UUID>) throws {
        var pairs = Set<BackupTransactionLabel>()
        for row in rows {
            if !transactionIDs.contains(row.transactionID) {
                throw BackupError.brokenReference("transaction label transaction \(row.transactionID)")
            }
            if !labelIDs.contains(row.labelID) {
                throw BackupError.brokenReference("transaction label label \(row.labelID)")
            }
            if !pairs.insert(row).inserted {
                throw BackupError.duplicateRelationship("transaction label")
            }
        }
    }

    private static func validateImportFingerprints(_ transactions: [BackupTransaction]) throws {
        var fingerprints = Set<String>()
        for transaction in transactions {
            guard let fingerprint = transaction.importFingerprint, !fingerprint.isEmpty else { continue }
            if !fingerprints.insert(fingerprint).inserted {
                throw BackupError.duplicateImportFingerprint(fingerprint)
            }
        }
    }

    private static func validateTransferPairs(_ transactions: [BackupTransaction]) throws {
        let byID = Dictionary(uniqueKeysWithValues: transactions.map { ($0.id, $0) })
        for transaction in transactions where transaction.type == .transferOut || transaction.type == .transferIn {
            guard let linkedTransferID = transaction.linkedTransferID, let linked = byID[linkedTransferID] else {
                throw BackupError.invalidTransferPair("transaction \(transaction.id) is missing its linked transfer")
            }
            guard linked.linkedTransferID == transaction.id else {
                throw BackupError.invalidTransferPair("transaction \(transaction.id) is not linked back")
            }
            guard transaction.amountMinor == linked.amountMinor else {
                throw BackupError.invalidTransferPair("transaction \(transaction.id) amount does not match")
            }
            guard transaction.walletID != linked.walletID else {
                throw BackupError.invalidTransferPair("transaction \(transaction.id) uses the same wallet on both sides")
            }
            switch (transaction.type, linked.type) {
            case (.transferOut, .transferIn), (.transferIn, .transferOut):
                break
            default:
                throw BackupError.invalidTransferPair("transaction \(transaction.id) is not paired with the opposite transfer type")
            }
        }
    }
}

public struct TransactionDraft: Identifiable, Codable, Hashable, Sendable {
    public enum Kind: String, CaseIterable, Codable, Sendable {
        case expense
        case income
        case transfer
    }

    public var id: UUID?
    public var kind: Kind
    public var walletID: UUID
    public var destinationWalletID: UUID?
    public var amountMinor: Int64
    public var occurredAt: Date
    public var categoryID: UUID?
    public var labelIDs: [UUID]
    public var merchant: String
    public var note: String
    public var source: TransactionSource
    public var recurringTemplateID: UUID?
    public var recurringInstanceID: UUID?
    public var importJobID: UUID?
    public var importFingerprint: String?

    public init(
        id: UUID? = nil,
        kind: Kind,
        walletID: UUID,
        destinationWalletID: UUID? = nil,
        amountMinor: Int64,
        occurredAt: Date,
        categoryID: UUID? = nil,
        labelIDs: [UUID] = [],
        merchant: String = "",
        note: String = "",
        source: TransactionSource = .manual,
        recurringTemplateID: UUID? = nil,
        recurringInstanceID: UUID? = nil,
        importJobID: UUID? = nil,
        importFingerprint: String? = nil
    ) {
        self.id = id
        self.kind = kind
        self.walletID = walletID
        self.destinationWalletID = destinationWalletID
        self.amountMinor = amountMinor
        self.occurredAt = occurredAt
        self.categoryID = categoryID
        self.labelIDs = labelIDs
        self.merchant = merchant
        self.note = note
        self.source = source
        self.recurringTemplateID = recurringTemplateID
        self.recurringInstanceID = recurringInstanceID
        self.importJobID = importJobID
        self.importFingerprint = importFingerprint
    }
}

public struct TransactionQuery: Sendable, Equatable {
    public var walletID: UUID?
    public var categoryID: UUID?
    public var labelID: UUID?
    public var searchText: String
    public var startDate: Date?
    public var endDate: Date?
    public var kinds: Set<TransactionDraft.Kind>

    public init(
        walletID: UUID? = nil,
        categoryID: UUID? = nil,
        labelID: UUID? = nil,
        searchText: String = "",
        startDate: Date? = nil,
        endDate: Date? = nil,
        kinds: Set<TransactionDraft.Kind> = Set(TransactionDraft.Kind.allCases)
    ) {
        self.walletID = walletID
        self.categoryID = categoryID
        self.labelID = labelID
        self.searchText = searchText
        self.startDate = startDate
        self.endDate = endDate
        self.kinds = kinds
    }
}

public struct TransactionListItem: Identifiable, Hashable, Sendable {
    public var id: UUID
    public var walletName: String
    public var amountMinor: Int64
    public var occurredAt: Date
    public var categoryName: String?
    public var categoryColorHex: String?
    public var categoryIconName: String?
    public var merchant: String
    public var note: String
    public var kind: TransactionDraft.Kind
    public var source: TransactionSource
    public var labels: [Label]
    public var dayKey: Int

    public var displayTitle: String {
        if let categoryName, !categoryName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return categoryName
        }
        if !merchant.isEmpty {
            return merchant
        }
        return kind.rawValue.capitalized
    }
}

public struct DashboardCategorySlice: Identifiable, Hashable, Sendable {
    public var id: UUID
    public var name: String
    public var colorHex: String?
    public var iconName: String?
    public var amountMinor: Int64
    public var transactionCount: Int
    public var percentage: Double
}

public struct DashboardSnapshot: Sendable {
    public var monthKey: Int
    public var walletFilterID: UUID?
    public var totalBalanceMinor: Int64
    public var monthIncomeMinor: Int64
    public var monthExpenseMinor: Int64
    public var monthNetMinor: Int64
    public var wealthHistory: [BalancePoint]
    public var categories: [DashboardCategorySlice]
    public var recentTransactions: [TransactionListItem]
}

public struct TimelineBarPoint: Identifiable, Hashable, Sendable {
    public var id: Int { periodKey }
    public var periodKey: Int
    public var incomeMinor: Int64
    public var expenseMinor: Int64
    public var incomeBarMinor: Int64 { incomeMinor }
    public var expenseBarMinor: Int64 { expenseMinor }
    public var xLabel: String
}

public struct TimelineSection: Identifiable, Hashable, Sendable {
    public var id: Int { periodKey }
    public var periodKey: Int
    public var periodLabel: String
    public var totalMinor: Int64
    public var items: [TransactionListItem]
}

public struct TimelineSnapshot: Sendable {
    public var anchorMonthKey: Int
    public var walletFilterID: UUID?
    public var heroCashFlowMinor: Int64
    public var bars: [TimelineBarPoint]
    public var sections: [TimelineSection]
    public var period: TimelinePeriod
}

public struct OverviewMonthPoint: Identifiable, Hashable, Sendable {
    public var id: Int { monthKey }
    public var monthKey: Int
    public var totalWealthMinor: Int64
    public var cashFlowMinor: Int64
    public var incomeMinor: Int64
    public var expenseMinor: Int64
}

public struct OverviewCategoryRow: Identifiable, Hashable, Sendable {
    public var id: UUID
    public var name: String
    public var kind: CategoryKind
    public var colorHex: String?
    public var iconName: String?
    public var amountMinor: Int64
    public var transactionCount: Int
    public var percentage: Double
}

public struct OverviewLabelRow: Identifiable, Hashable, Sendable {
    public var id: String { "\(labelID.uuidString)-\(kind.rawValue)" }
    public var labelID: UUID
    public var name: String
    public var kind: CategoryKind
    public var colorHex: String?
    public var amountMinor: Int64
    public var transactionCount: Int
    public var percentage: Double
}

public struct OverviewSnapshot: Sendable {
    public var selectedMonthKey: Int
    public var walletFilterID: UUID?
    public var months: [OverviewMonthPoint]
    public var totalWealthMinor: Int64
    public var monthCashFlowMinor: Int64
    public var monthIncomeMinor: Int64
    public var monthExpenseMinor: Int64
    public var categories: [OverviewCategoryRow]
    public var labels: [OverviewLabelRow]
}

public struct BalancePoint: Identifiable, Hashable, Sendable {
    public var id: Int { dayKey }
    public var dayKey: Int
    public var amountMinor: Int64
}

// DEPRECATED — Budgets feature is de-prioritized. Work stopped; do not modify or add tests until resumed.
public struct BudgetProgress: Identifiable, Hashable, Sendable {
    public var id: UUID
    public var budget: Budget
    public var category: Category
    public var spentMinor: Int64
    public var remainingMinor: Int64
    public var percentUsedBP: Int
}

public struct CategoryManagementItem: Identifiable, Hashable, Sendable {
    public var id: UUID { category.id }
    public var category: Category
    public var transactionCount: Int
    public var walletCount: Int
    public var isVisible: Bool
}

public struct TransactionComposerState: Sendable {
    public var selectedKind: TransactionDraft.Kind
    public var selectedCategoryID: UUID?
    public var amountText: String
    public var quickDateLabel: String?
    public var selectedLabelIDs: [UUID]

    public init(
        selectedKind: TransactionDraft.Kind,
        selectedCategoryID: UUID?,
        amountText: String,
        quickDateLabel: String?,
        selectedLabelIDs: [UUID]
    ) {
        self.selectedKind = selectedKind
        self.selectedCategoryID = selectedCategoryID
        self.amountText = amountText
        self.quickDateLabel = quickDateLabel
        self.selectedLabelIDs = selectedLabelIDs
    }
}

public struct CSVImportPreview: Sendable {
    public var headers: [String]
    public var sampleRows: [[String]]
    public var totalRows: Int
}

public struct CSVImportMapping: Sendable {
    public var dateColumn: String
    public var amountColumn: String?
    public var debitColumn: String?
    public var creditColumn: String?
    public var typeColumn: String?
    public var walletColumn: String?
    public var currencyColumn: String?
    public var merchantColumn: String?
    public var noteColumn: String?
    public var categoryColumn: String?
    public var labelsColumn: String?
    public var authorColumn: String?
    public var walletID: UUID
    public var defaultKind: TransactionDraft.Kind

    public init(
        dateColumn: String,
        amountColumn: String?,
        debitColumn: String?,
        creditColumn: String?,
        merchantColumn: String?,
        noteColumn: String?,
        categoryColumn: String?,
        labelsColumn: String?,
        walletID: UUID,
        defaultKind: TransactionDraft.Kind,
        typeColumn: String? = nil,
        walletColumn: String? = nil,
        currencyColumn: String? = nil,
        authorColumn: String? = nil
    ) {
        self.dateColumn = dateColumn
        self.amountColumn = amountColumn
        self.debitColumn = debitColumn
        self.creditColumn = creditColumn
        self.typeColumn = typeColumn
        self.walletColumn = walletColumn
        self.currencyColumn = currencyColumn
        self.merchantColumn = merchantColumn
        self.noteColumn = noteColumn
        self.categoryColumn = categoryColumn
        self.labelsColumn = labelsColumn
        self.authorColumn = authorColumn
        self.walletID = walletID
        self.defaultKind = defaultKind
    }
}

public struct CSVImportResult: Sendable {
    public var job: ImportJob
    public var insertedTransactions: Int
    public var duplicateRows: Int
    public var invalidRows: Int
    public var affectedMonths: Set<Int>
    public var rowErrors: [CSVRowError]
}

public struct PreparedImportRow: Sendable {
    public var rowNumber: Int
    public var draft: TransactionDraft
    public var fingerprint: String
    public var sourceName: String
    public var rawCategoryName: String?
    public var rawLabelNames: [String]
    public var currency: String?
    public var categoryIconName: String?
    public var categoryColorHex: String?

    public init(
        rowNumber: Int,
        draft: TransactionDraft,
        fingerprint: String,
        sourceName: String,
        rawCategoryName: String? = nil,
        rawLabelNames: [String] = [],
        currency: String? = nil,
        categoryIconName: String? = nil,
        categoryColorHex: String? = nil
    ) {
        self.rowNumber = rowNumber
        self.draft = draft
        self.fingerprint = fingerprint
        self.sourceName = sourceName
        self.rawCategoryName = rawCategoryName
        self.rawLabelNames = rawLabelNames
        self.currency = currency
        self.categoryIconName = categoryIconName
        self.categoryColorHex = categoryColorHex
    }
}

public struct CSVRowError: Identifiable, Hashable, Sendable {
    public var id: Int { rowNumber }
    public var rowNumber: Int
    public var message: String
}

public struct DefaultCategoryDefinition: Hashable, Sendable {
    public var id: UUID
    public var name: String
    public var kind: CategoryKind
    public var iconName: String
    public var colorHex: String
}

public enum SeedCategories {
    public static let all: [DefaultCategoryDefinition] = [
        .init(id: UUID(uuidString: "11111111-1111-1111-1111-111111111111")!, name: "Groceries", kind: .expense, iconName: "cart", colorHex: "#1CC389"),
        .init(id: UUID(uuidString: "11111111-1111-1111-1111-111111111112")!, name: "Restaurants", kind: .expense, iconName: "cup.and.saucer.fill", colorHex: "#64D1D5"),
        .init(id: UUID(uuidString: "11111111-1111-1111-1111-111111111113")!, name: "Transport", kind: .expense, iconName: "tram.fill", colorHex: "#FFC400"),
        .init(id: UUID(uuidString: "11111111-1111-1111-1111-111111111114")!, name: "Housing", kind: .expense, iconName: "house.fill", colorHex: "#E5862F"),
        .init(id: UUID(uuidString: "11111111-1111-1111-1111-111111111115")!, name: "Utilities", kind: .expense, iconName: "bolt.fill", colorHex: "#6FD03B"),
        .init(id: UUID(uuidString: "11111111-1111-1111-1111-111111111116")!, name: "Health", kind: .expense, iconName: "cross.case.fill", colorHex: "#E96176"),
        .init(id: UUID(uuidString: "11111111-1111-1111-1111-111111111117")!, name: "Shopping", kind: .expense, iconName: "bag.fill", colorHex: "#5FD4BF"),
        .init(id: UUID(uuidString: "11111111-1111-1111-1111-111111111118")!, name: "Entertainment", kind: .expense, iconName: "theatermasks.fill", colorHex: "#FFA600"),
        .init(id: UUID(uuidString: "11111111-1111-1111-1111-111111111119")!, name: "Education", kind: .expense, iconName: "graduationcap.fill", colorHex: "#4A80C1"),
        .init(id: UUID(uuidString: "11111111-1111-1111-1111-111111111120")!, name: "Travel", kind: .expense, iconName: "airplane", colorHex: "#EE5DA7"),
        .init(id: UUID(uuidString: "11111111-1111-1111-1111-111111111121")!, name: "Gifts", kind: .expense, iconName: "gift.fill", colorHex: "#FF5E57"),
        .init(id: UUID(uuidString: "11111111-1111-1111-1111-111111111122")!, name: "Other Expense", kind: .expense, iconName: "questionmark.app.fill", colorHex: "#7E57C2"),
        .init(id: UUID(uuidString: "22222222-2222-2222-2222-222222222111")!, name: "Salary", kind: .income, iconName: "banknote.fill", colorHex: "#2AAAD2"),
        .init(id: UUID(uuidString: "22222222-2222-2222-2222-222222222112")!, name: "Bonus", kind: .income, iconName: "crown.fill", colorHex: "#F7A72A"),
        .init(id: UUID(uuidString: "22222222-2222-2222-2222-222222222113")!, name: "Gift Income", kind: .income, iconName: "gift.fill", colorHex: "#FF5E57"),
        .init(id: UUID(uuidString: "22222222-2222-2222-2222-222222222114")!, name: "Refund", kind: .income, iconName: "arrow.uturn.backward.circle.fill", colorHex: "#16C790"),
        .init(id: UUID(uuidString: "22222222-2222-2222-2222-222222222115")!, name: "Other Income", kind: .income, iconName: "sparkles", colorHex: "#87C56A"),
    ]
}

public enum CashRunwayError: Error, LocalizedError, Equatable {
    case validation(String)
    case notFound
    case invalidState(String)

    public var errorDescription: String? {
        switch self {
        case let .validation(message), let .invalidState(message):
            message
        case .notFound:
            "Requested record was not found."
        }
    }
}
