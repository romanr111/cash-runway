import Foundation

public enum DeletePeriod: String, CaseIterable, Sendable, Identifiable {
    case today
    case thisMonth
    case thisYear

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
    public let expenseMinor: Int64
    public let incomeMinor: Int64

    public init(count: Int, expenseMinor: Int64 = 0, incomeMinor: Int64 = 0) {
        self.count = count
        self.expenseMinor = expenseMinor
        self.incomeMinor = incomeMinor
    }
}

/// An immutable snapshot of what a bulk delete will remove.
///
/// Created during preview and passed to execution so the exact row IDs shown to
/// the user are the rows that are deleted. `referenceDayKey`,
/// `referenceMonthKey`, and `referenceYear` freeze the calendar scope at the
/// time of preview; execution recomputes the matching IDs from those keys and
/// aborts if the set has changed.
public struct TransactionDeletionPlan: Equatable, Sendable, Identifiable {
    public let id: UUID
    public let period: DeletePeriod
    public let referenceDayKey: Int
    public let referenceMonthKey: Int
    public let referenceYear: Int
    public let transactionIDs: [UUID]
    public let summary: TransactionDeletionSummary

    public var count: Int { summary.count }
    public var expenseMinor: Int64 { summary.expenseMinor }
    public var incomeMinor: Int64 { summary.incomeMinor }

    public init(
        id: UUID = UUID(),
        period: DeletePeriod,
        referenceDayKey: Int,
        referenceMonthKey: Int,
        referenceYear: Int,
        transactionIDs: [UUID],
        summary: TransactionDeletionSummary
    ) {
        self.id = id
        self.period = period
        self.referenceDayKey = referenceDayKey
        self.referenceMonthKey = referenceMonthKey
        self.referenceYear = referenceYear
        self.transactionIDs = transactionIDs
        self.summary = summary
    }
}
