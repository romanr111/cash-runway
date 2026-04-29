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
    case importCSV = "import_csv"
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
    public var createdAt: Date
    public var updatedAt: Date

    public init(id: UUID, walletID: UUID, type: TransactionKind, linkedTransferID: UUID?, amountMinor: Int64, occurredAt: Date, localDayKey: Int, localMonthKey: Int, categoryID: UUID?, merchant: String?, note: String?, isDeleted: Bool, source: TransactionSource, recurringTemplateID: UUID?, recurringInstanceID: UUID?, createdAt: Date, updatedAt: Date) {
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
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

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
    public var startedAt: Date
    public var finishedAt: Date?
    public var errorSummary: String?
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
        recurringInstanceID: UUID? = nil
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
    }
}

public struct TransactionQuery: Sendable {
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
    public var id: Int { monthKey }
    public var monthKey: Int
    public var incomeMinor: Int64
    public var expenseMinor: Int64
    public var incomeBarMinor: Int64 { incomeMinor }
    public var expenseBarMinor: Int64 { expenseMinor }
}

public struct TransactionDaySection: Identifiable, Hashable, Sendable {
    public var id: Int { dayKey }
    public var dayKey: Int
    public var totalMinor: Int64
    public var items: [TransactionListItem]
}

public struct TimelineSnapshot: Sendable {
    public var monthKey: Int
    public var walletFilterID: UUID?
    public var heroCashFlowMinor: Int64
    public var monthlyBars: [TimelineBarPoint]
    public var sections: [TransactionDaySection]
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
    public var affectedMonths: Set<Int>
    public var rowErrors: [CSVRowError]
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
