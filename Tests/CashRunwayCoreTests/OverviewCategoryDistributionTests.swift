import Foundation
import Testing
@testable import CashRunwayCore

@Suite(.serialized)
struct OverviewCategoryDistributionTests {
    @Test func distributionUsesAbsoluteAmountsAndSortsDescending() {
        let rent = category(name: "Rent", amountMinor: -44_200, percentage: .nan)
        let healthcare = category(name: "Healthcare", amountMinor: 4_441, percentage: .infinity)
        let food = category(name: "Food & Drink", amountMinor: 2_325, percentage: 42)

        let distribution = OverviewCategoryDistributionLayout.distribution(for: [food, rent, healthcare])

        #expect(distribution.totalAmountMinor == 50_966)
        #expect(distribution.segments.map(\.category.name) == ["Rent", "Healthcare", "Food & Drink"])
        #expect(distribution.segments.map(\.category.amountMinor) == [44_200, 4_441, 2_325])
        #expect(abs(distribution.segments.reduce(0.0) { $0 + $1.sweepDegrees } - 360.0) < 0.001)
    }

    @Test func distributionIgnoresZeroAndInvalidAmounts() {
        let valid = category(name: "Transport", amountMinor: 12_750, percentage: .nan)
        let zero = category(name: "Zero", amountMinor: 0, percentage: 0)
        let overflow = category(name: "Invalid", amountMinor: Int64.min, percentage: .infinity)

        let distribution = OverviewCategoryDistributionLayout.distribution(for: [zero, overflow, valid])

        #expect(distribution.totalAmountMinor == 12_750)
        #expect(distribution.segments.count == 1)
        #expect(distribution.segments[0].category.name == "Transport")
        #expect(distribution.segments[0].sweepDegrees == 360)
        #expect(distribution.segments[0].category.percentage == 1)
    }

    @Test func distributionReturnsEmptyFallbackForNoValidCategories() {
        let distribution = OverviewCategoryDistributionLayout.distribution(for: [
            category(name: "Zero", amountMinor: 0, percentage: 0),
            category(name: "Invalid", amountMinor: Int64.min, percentage: .nan),
        ])

        #expect(distribution.totalAmountMinor == 0)
        #expect(distribution.segments.isEmpty)
    }

    @Test func collapsedSelectionFallsBackToLargestVisibleCategory() {
        let rows = [
            category(name: "A", amountMinor: 600, percentage: 0),
            category(name: "B", amountMinor: 500, percentage: 0),
            category(name: "C", amountMinor: 400, percentage: 0),
            category(name: "D", amountMinor: 300, percentage: 0),
            category(name: "E", amountMinor: 200, percentage: 0),
            category(name: "Hidden", amountMinor: 100, percentage: 0),
        ]
        let distribution = OverviewCategoryDistributionLayout.distribution(for: rows)
        let categories = distribution.segments.map(\.category)
        let hiddenID = categories[5].id

        let selected = OverviewCategoryDisplayLayout.selectedCategory(
            in: categories,
            selectedCategoryID: hiddenID,
            showsAllCategories: false
        )

        #expect(selected?.name == "A")
    }

    @Test func hiddenSegmentSelectionRequestsExpansion() {
        let rows = [
            category(name: "A", amountMinor: 600, percentage: 0),
            category(name: "B", amountMinor: 500, percentage: 0),
            category(name: "C", amountMinor: 400, percentage: 0),
            category(name: "D", amountMinor: 300, percentage: 0),
            category(name: "E", amountMinor: 200, percentage: 0),
            category(name: "Hidden", amountMinor: 100, percentage: 0),
        ]
        let distribution = OverviewCategoryDistributionLayout.distribution(for: rows)
        let categories = distribution.segments.map(\.category)

        #expect(OverviewCategoryDisplayLayout.shouldExpandForSelection(
            categoryID: categories[5].id,
            in: categories,
            showsAllCategories: false
        ))
        #expect(!OverviewCategoryDisplayLayout.shouldExpandForSelection(
            categoryID: categories[0].id,
            in: categories,
            showsAllCategories: false
        ))
    }

    private func category(
        name: String,
        amountMinor: Int64,
        percentage: Double
    ) -> OverviewCategoryRow {
        OverviewCategoryRow(
            id: UUID(),
            name: name,
            kind: .expense,
            colorHex: "#60788A",
            iconName: "tag.fill",
            amountMinor: amountMinor,
            transactionCount: 1,
            percentage: percentage
        )
    }
}
