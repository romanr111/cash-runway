import CashRunwayCore
import Foundation

/// Pure UI presentation adapter over `TimelineSnapshot`.
///
/// Decouples `DashboardView` from `TimelineSnapshot` internals. The selected-period
/// summary values (net cash flow, income, expense) and the expense comparison are all
/// sourced from one consistent snapshot, never recomputed from `allBars`.
public struct TimelineSummaryAdapter: Equatable, Sendable {
    let heroCashFlowMinor: Int64
    let incomeMinor: Int64
    let expenseMinor: Int64
    let comparison: TimelineComparison?

    /// Builds the adapter from the selected-period snapshot.
    /// The selected bar is the bar whose `periodKey` matches the snapshot anchor;
    /// it is the single source of truth for headline values.
    init(snapshot: TimelineSnapshot?) {
        guard let snapshot else {
            self.heroCashFlowMinor = 0
            self.incomeMinor = 0
            self.expenseMinor = 0
            self.comparison = nil
            return
        }

        let selectedBar = Self.selectedBar(in: snapshot)
        let income = selectedBar?.incomeMinor ?? 0
        let expense = selectedBar?.expenseMinor ?? 0
        self.heroCashFlowMinor = snapshot.heroCashFlowMinor
        self.incomeMinor = income
        self.expenseMinor = expense
        self.comparison = snapshot.comparison
    }

    private static func selectedBar(in snapshot: TimelineSnapshot) -> TimelineBarPoint? {
        let anchorPeriodKey: Int
        switch snapshot.period {
        case .month:
            anchorPeriodKey = snapshot.anchorMonthKey
        case .year:
            anchorPeriodKey = snapshot.anchorMonthKey / 100
        }
        return snapshot.bars.first(where: { $0.periodKey == anchorPeriodKey }) ?? snapshot.bars.last
    }
}
