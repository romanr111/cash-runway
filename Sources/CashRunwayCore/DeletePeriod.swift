import Foundation

public enum DeletePeriod: String, CaseIterable, Sendable, Identifiable {
    case today
    case thisMonth
    case thisYear

    public var id: String { rawValue }
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
