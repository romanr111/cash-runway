import CashRunwayCore
import CashRunwayUIVM
import Testing
import Foundation

@Suite struct TimelineFilterPresentationTests {
    private let allKinds = Set(TransactionDraft.Kind.allCases)

    // MARK: - Badge counting

    @Test func emptyQueryHasZeroAdvancedFilters() {
        let presentation = TimelineFilterPresentation(query: TransactionQuery())
        #expect(presentation.activeAdvancedFilterCount == 0)
        #expect(!presentation.isSearchActive)
        #expect(!presentation.hasAnyFeedFilter)
    }

    @Test func searchTextDoesNotCountAsAdvancedFilter() {
        var query = TransactionQuery()
        query.searchText = "Bolt"
        let presentation = TimelineFilterPresentation(query: query)

        #expect(presentation.isSearchActive)
        #expect(presentation.activeAdvancedFilterCount == 0)
        #expect(presentation.hasAnyFeedFilter)
    }

    @Test func categoryFilterCountsAsOne() {
        var query = TransactionQuery()
        query.categoryID = UUID()
        let presentation = TimelineFilterPresentation(query: query)

        #expect(presentation.activeAdvancedFilterCount == 1)
    }

    @Test func labelFilterCountsAsOne() {
        var query = TransactionQuery()
        query.labelID = UUID()
        let presentation = TimelineFilterPresentation(query: query)

        #expect(presentation.activeAdvancedFilterCount == 1)
    }

    @Test func nonAllKindsFilterCountsAsOne() {
        var query = TransactionQuery()
        query.kinds = [.expense]
        let presentation = TimelineFilterPresentation(query: query)

        #expect(presentation.activeAdvancedFilterCount == 1)
    }

    @Test func allKindsDoesNotCount() {
        var query = TransactionQuery()
        query.kinds = allKinds
        let presentation = TimelineFilterPresentation(query: query)

        #expect(presentation.activeAdvancedFilterCount == 0)
    }

    @Test func dateRangeCountsAsOne() {
        var query = TransactionQuery()
        query.startDate = Date(timeIntervalSince1970: 1_000_000)
        query.endDate = Date(timeIntervalSince1970: 2_000_000)
        let presentation = TimelineFilterPresentation(query: query)

        #expect(presentation.activeAdvancedFilterCount == 1)
        #expect(presentation.isDateRangeActive)
    }

    @Test func multipleAdvancedFiltersAccumulate() {
        var query = TransactionQuery()
        query.categoryID = UUID()
        query.labelID = UUID()
        query.kinds = [.expense]
        query.startDate = Date(timeIntervalSince1970: 1_000_000)
        query.endDate = Date(timeIntervalSince1970: 2_000_000)
        let presentation = TimelineFilterPresentation(query: query)

        #expect(presentation.activeAdvancedFilterCount == 4)
    }

    // MARK: - Reset semantics

    @Test func resetSearchPreservesAdvancedFilters() {
        var query = TransactionQuery()
        query.searchText = "Bolt"
        query.categoryID = UUID()
        query.kinds = [.expense]

        let reset = TimelineFilterPresentation.resetSearch(query: query)
        #expect(reset.searchText.isEmpty)
        #expect(reset.categoryID == query.categoryID)
        #expect(reset.kinds == query.kinds)
    }

    @Test func resetFiltersPreservesSearchText() {
        var query = TransactionQuery()
        query.searchText = "Bolt"
        query.categoryID = UUID()
        query.labelID = UUID()
        query.kinds = [.expense]
        query.startDate = Date(timeIntervalSince1970: 1_000_000)
        query.endDate = Date(timeIntervalSince1970: 2_000_000)

        let reset = TimelineFilterPresentation.resetFilters(query: query)
        #expect(reset.searchText == "Bolt")
        #expect(reset.categoryID == nil)
        #expect(reset.labelID == nil)
        #expect(reset.kinds == allKinds)
        #expect(reset.startDate == nil)
        #expect(reset.endDate == nil)
    }

    @Test func clearAllRemovesSearchAndFilters() {
        var query = TransactionQuery()
        query.searchText = "Bolt"
        query.categoryID = UUID()
        query.kinds = [.expense]

        let reset = TimelineFilterPresentation.clearAll(query: query)
        #expect(reset.searchText.isEmpty)
        #expect(reset.categoryID == nil)
        #expect(reset.kinds == allKinds)
    }

    // MARK: - Apply validation

    @Test func applyClearsDatesWhenDateRangeDisabled() {
        var draft = TransactionQuery()
        draft.startDate = Date(timeIntervalSince1970: 1_000_000)
        draft.endDate = Date(timeIntervalSince1970: 2_000_000)

        let applied = TimelineFilterPresentation.apply(draft: draft, usesDateRange: false, walletID: nil)
        #expect(applied.startDate == nil)
        #expect(applied.endDate == nil)
    }

    @Test func applyKeepsDatesWhenDateRangeEnabled() {
        var draft = TransactionQuery()
        draft.startDate = Date(timeIntervalSince1970: 1_000_000)
        draft.endDate = Date(timeIntervalSince1970: 2_000_000)

        let applied = TimelineFilterPresentation.apply(draft: draft, usesDateRange: true, walletID: nil)
        #expect(applied.startDate == draft.startDate)
        #expect(applied.endDate == draft.endDate)
    }

    @Test func validDateRangeWhenEitherSideNil() {
        #expect(TimelineFilterPresentation.isDateRangeValid(startDate: nil, endDate: nil))
        #expect(TimelineFilterPresentation.isDateRangeValid(startDate: Date(), endDate: nil))
        #expect(TimelineFilterPresentation.isDateRangeValid(startDate: nil, endDate: Date()))
    }

    @Test func invalidWhenStartAfterEnd() {
        let start = Date(timeIntervalSince1970: 2_000_000)
        let end = Date(timeIntervalSince1970: 1_000_000)
        #expect(!TimelineFilterPresentation.isDateRangeValid(startDate: start, endDate: end))
    }

    @Test func validWhenStartEqualsEnd() {
        let date = Date(timeIntervalSince1970: 1_000_000)
        #expect(TimelineFilterPresentation.isDateRangeValid(startDate: date, endDate: date))
    }
}
