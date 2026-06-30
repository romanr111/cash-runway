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
    public let totalBalance: AgentMoneyDTO
    public let monthIncome: AgentMoneyDTO
    public let monthExpense: AgentMoneyDTO
    public let monthNet: AgentMoneyDTO
    public let categoryRows: [AgentCategoryRowDTO]
    public let walletSummaries: [AgentWalletSummaryDTO]

    public init(
        totalBalance: AgentMoneyDTO,
        monthIncome: AgentMoneyDTO,
        monthExpense: AgentMoneyDTO,
        monthNet: AgentMoneyDTO,
        categoryRows: [AgentCategoryRowDTO] = [],
        walletSummaries: [AgentWalletSummaryDTO] = []
    ) {
        self.totalBalance = totalBalance
        self.monthIncome = monthIncome
        self.monthExpense = monthExpense
        self.monthNet = monthNet
        self.categoryRows = categoryRows
        self.walletSummaries = walletSummaries
    }
}

public struct AgentMoneyDTO: Codable, Hashable, Sendable {
    public let amountMinor: Int64
    public let currencyCode: String
    public let scale: Int

    public init(amountMinor: Int64, currencyCode: String, scale: Int = 2) {
        self.amountMinor = amountMinor
        self.currencyCode = currencyCode
        self.scale = scale
    }
}

public struct AgentWalletSummaryDTO: Codable, Hashable, Sendable {
    public let handle: String
    public let name: String
    public let kind: WalletKind
    public let currentBalance: AgentMoneyDTO

    public init(
        handle: String,
        name: String,
        kind: WalletKind,
        currentBalance: AgentMoneyDTO
    ) {
        self.handle = handle
        self.name = name
        self.kind = kind
        self.currentBalance = currentBalance
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
    public let amount: AgentMoneyDTO
    public let transactionCount: Int

    public init(
        name: String,
        kind: CategoryKind,
        amount: AgentMoneyDTO,
        transactionCount: Int
    ) {
        self.name = name
        self.kind = kind
        self.amount = amount
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
    public let amount: AgentMoneyDTO
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
        amount: AgentMoneyDTO,
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
        self.amount = amount
        self.categoryName = categoryName
        self.merchantPreview = merchantPreview
        self.notePreview = notePreview
        self.labels = labels
        self.source = source
    }
}

public enum AgentBankSyncHealth: String, Codable, Sendable {
    case connected
    case disconnected
    case syncFailed
    case tokenInvalid
    case rateLimited
    case unknown
}

public struct AgentBankConnectionStatusResponse: Codable, Sendable {
    public let provider: BankProvider
    public let isConnected: Bool
    public let enabledAccountCount: Int
    public let health: AgentBankSyncHealth
    public let sanitizedErrorHint: String?

    public init(
        provider: BankProvider,
        isConnected: Bool,
        enabledAccountCount: Int,
        health: AgentBankSyncHealth,
        sanitizedErrorHint: String? = nil
    ) {
        self.provider = provider
        self.isConnected = isConnected
        self.enabledAccountCount = enabledAccountCount
        self.health = health
        self.sanitizedErrorHint = sanitizedErrorHint
    }
}
