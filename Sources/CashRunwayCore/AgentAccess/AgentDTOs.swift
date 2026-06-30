import Foundation

// MARK: - Requests

public struct AgentOverviewRequest: Codable, Hashable, Sendable {
    public var monthKey: Int?

    public init(monthKey: Int? = nil) {
        self.monthKey = monthKey
    }
}

public struct AgentTransactionsRequest: Codable, Hashable, Sendable {
    public var walletIDs: Set<UUID>?
    public var startDate: Date?
    public var endDate: Date?

    public init(
        walletIDs: Set<UUID>? = nil,
        startDate: Date? = nil,
        endDate: Date? = nil
    ) {
        self.walletIDs = walletIDs
        self.startDate = startDate
        self.endDate = endDate
    }
}

// MARK: - Responses

public struct AgentOverviewResponse: Codable, Sendable {
    public let totalBalanceMinor: Int64
    public let monthIncomeMinor: Int64
    public let monthExpenseMinor: Int64
    public let monthNetMinor: Int64
    public let categoryRows: [AgentCategoryRowDTO]
    public let walletSummaries: [AgentWalletSummaryDTO]

    public init(
        totalBalanceMinor: Int64,
        monthIncomeMinor: Int64,
        monthExpenseMinor: Int64,
        monthNetMinor: Int64,
        categoryRows: [AgentCategoryRowDTO] = [],
        walletSummaries: [AgentWalletSummaryDTO] = []
    ) {
        self.totalBalanceMinor = totalBalanceMinor
        self.monthIncomeMinor = monthIncomeMinor
        self.monthExpenseMinor = monthExpenseMinor
        self.monthNetMinor = monthNetMinor
        self.categoryRows = categoryRows
        self.walletSummaries = walletSummaries
    }
}

public struct AgentWalletSummaryDTO: Codable, Hashable, Sendable {
    public let handle: String
    public let name: String
    public let kind: WalletKind
    public let currentBalanceMinor: Int64
    public let currencyCode: String

    public init(
        handle: String,
        name: String,
        kind: WalletKind,
        currentBalanceMinor: Int64,
        currencyCode: String
    ) {
        self.handle = handle
        self.name = name
        self.kind = kind
        self.currentBalanceMinor = currentBalanceMinor
        self.currencyCode = currencyCode
    }
}

public struct AgentWalletsResponse: Codable, Sendable {
    public let wallets: [AgentWalletSummaryDTO]

    public init(wallets: [AgentWalletSummaryDTO]) {
        self.wallets = wallets
    }
}

public struct AgentCategoriesResponse: Codable, Sendable {
    public let categories: [AgentCategoryRowDTO]

    public init(categories: [AgentCategoryRowDTO]) {
        self.categories = categories
    }
}

public struct AgentCategoryRowDTO: Codable, Hashable, Sendable {
    public let name: String
    public let kind: CategoryKind
    public let amountMinor: Int64
    public let transactionCount: Int

    public init(
        name: String,
        kind: CategoryKind,
        amountMinor: Int64,
        transactionCount: Int
    ) {
        self.name = name
        self.kind = kind
        self.amountMinor = amountMinor
        self.transactionCount = transactionCount
    }
}

public struct AgentTransactionsResponse: Codable, Sendable {
    public let transactions: [AgentTransactionDTO]
    public let returnedCount: Int
    public let truncatedToMax: Bool

    public init(
        transactions: [AgentTransactionDTO],
        returnedCount: Int,
        truncatedToMax: Bool
    ) {
        self.transactions = transactions
        self.returnedCount = returnedCount
        self.truncatedToMax = truncatedToMax
    }
}

public struct AgentTransactionDTO: Codable, Hashable, Sendable {
    public let handle: String
    public let occurredAt: Date
    public let walletDisplayName: String
    public let kind: TransactionKind
    public let amountMinor: Int64
    public let currencyCode: String
    public let categoryName: String?
    public let merchantPreview: String?
    public let notePreview: String?
    public let labels: [String]
    public let source: TransactionSource

    public init(
        handle: String,
        occurredAt: Date,
        walletDisplayName: String,
        kind: TransactionKind,
        amountMinor: Int64,
        currencyCode: String,
        categoryName: String? = nil,
        merchantPreview: String? = nil,
        notePreview: String? = nil,
        labels: [String] = [],
        source: TransactionSource
    ) {
        self.handle = handle
        self.occurredAt = occurredAt
        self.walletDisplayName = walletDisplayName
        self.kind = kind
        self.amountMinor = amountMinor
        self.currencyCode = currencyCode
        self.categoryName = categoryName
        self.merchantPreview = merchantPreview
        self.notePreview = notePreview
        self.labels = labels
        self.source = source
    }
}

public struct AgentBankConnectionStatusResponse: Codable, Sendable {
    public let provider: BankProvider
    public let isConnected: Bool
    public let enabledAccountCount: Int
    public let lastSyncError: String?

    public init(
        provider: BankProvider,
        isConnected: Bool,
        enabledAccountCount: Int,
        lastSyncError: String?
    ) {
        self.provider = provider
        self.isConnected = isConnected
        self.enabledAccountCount = enabledAccountCount
        self.lastSyncError = lastSyncError
    }
}
