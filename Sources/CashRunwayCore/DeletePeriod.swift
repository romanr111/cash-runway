import Foundation

public enum DeletePeriod: String, CaseIterable, Sendable, Identifiable {
    case today
    case thisMonth
    case thisYear
    case allHistory

    public var id: String { rawValue }
}

public enum TransactionDeletionError: Error, Equatable, Sendable, LocalizedError {
    case planStale

    public var errorDescription: String? {
        switch self {
        case .planStale:
            return L10n.string("The transactions to delete changed. Please review the period again.")
        }
    }
}

public struct TransactionDeletionSummary: Equatable, Sendable {
    public let count: Int
    public let displayCount: Int
    public let expenseMinor: Int64
    public let incomeMinor: Int64
    public let currencyCodes: Set<String>

    public var hasExpenseImpact: Bool { expenseMinor > 0 }
    public var hasIncomeImpact: Bool { incomeMinor != 0 }
    public var hasFinancialImpact: Bool { hasExpenseImpact || hasIncomeImpact }
    public var isMixedCurrency: Bool { currencyCodes.count > 1 }

    public init(count: Int, displayCount: Int, expenseMinor: Int64 = 0, incomeMinor: Int64 = 0, currencyCodes: Set<String> = []) {
        self.count = count
        self.displayCount = displayCount
        self.expenseMinor = expenseMinor
        self.incomeMinor = incomeMinor
        self.currencyCodes = currencyCodes
    }
}

/// Outcome of executing a bulk-delete plan.
public struct TransactionDeletionResult: Equatable, Sendable {
    public let deletedCount: Int
    public let refreshSuccess: Bool

    public init(deletedCount: Int, refreshSuccess: Bool) {
        self.deletedCount = deletedCount
        self.refreshSuccess = refreshSuccess
    }
}

/// Immutable fingerprint of a single transaction row at preview time.
/// Execution compares these snapshots to detect same-ID mutations.
public struct TransactionDeletionItem: Equatable, Sendable, Hashable {
    public let id: UUID
    public let updatedAt: String

    public init(id: UUID, updatedAt: String) {
        self.id = id
        self.updatedAt = updatedAt
    }
}

/// An immutable snapshot of what a bulk delete will remove.
///
/// Created during preview and passed to execution so the exact row IDs shown to
/// the user are the rows that are deleted. `referenceDayKey`,
/// `referenceMonthKey`, and `referenceYear` freeze the calendar scope at the
/// time of preview; execution recomputes the matching items from those keys and
/// aborts if the set has changed — including same-ID field mutations detected
/// via `updatedAt` fingerprints.
public struct TransactionDeletionPlan: Equatable, Sendable, Identifiable {
    public let id: UUID
    public let period: DeletePeriod
    public let referenceDayKey: Int
    public let referenceMonthKey: Int
    public let referenceYear: Int
    public let items: [TransactionDeletionItem]
    public let summary: TransactionDeletionSummary

    public var transactionIDs: [UUID] { items.map(\.id) }
    public var count: Int { summary.count }
    public var displayCount: Int { summary.displayCount }
    public var expenseMinor: Int64 { summary.expenseMinor }
    public var incomeMinor: Int64 { summary.incomeMinor }
    public var hasExpenseImpact: Bool { summary.hasExpenseImpact }
    public var hasIncomeImpact: Bool { summary.hasIncomeImpact }
    public var hasFinancialImpact: Bool { summary.hasFinancialImpact }

    public init(
        id: UUID = UUID(),
        period: DeletePeriod,
        referenceDayKey: Int,
        referenceMonthKey: Int,
        referenceYear: Int,
        items: [TransactionDeletionItem],
        summary: TransactionDeletionSummary
    ) {
        self.id = id
        self.period = period
        self.referenceDayKey = referenceDayKey
        self.referenceMonthKey = referenceMonthKey
        self.referenceYear = referenceYear
        self.items = items
        self.summary = summary
    }
}
