import Foundation

public enum DeletePeriod: String, CaseIterable, Sendable, Identifiable {
    case today
    case thisMonth
    case thisYear

    public var id: String { rawValue }
}

public struct TransactionDeletionSummary: Equatable, Sendable {
    public let count: Int
    public let totalAmountMinor: Int64

    public init(count: Int, totalAmountMinor: Int64) {
        self.count = count
        self.totalAmountMinor = totalAmountMinor
    }
}
