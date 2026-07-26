import CashRunwayCore
import Foundation

/// Pure presentation helper for the Timeline filter bar and search/filter sheet.
///
/// Calculates the advanced-filter badge count (excluding text search, wallet, and
/// selected period) and distinguishes search vs. filters entry modes. This type is
/// intentionally stateless so it can be unit-tested without UI dependencies.
public struct TimelineFilterPresentation: Equatable, Sendable {
    public enum EntryMode: Equatable, Sendable {
        case search
        case filters
    }

    public let searchText: String
    public let categoryID: UUID?
    public let labelID: UUID?
    public let kinds: Set<TransactionDraft.Kind>
    public let startDate: Date?
    public let endDate: Date?

    public init(query: TransactionQuery) {
        self.searchText = query.searchText
        self.categoryID = query.categoryID
        self.labelID = query.labelID
        self.kinds = query.kinds
        self.startDate = query.startDate
        self.endDate = query.endDate
    }

    /// Counts advanced feed filters only. Excludes text search, wallet, and selected period.
    public var activeAdvancedFilterCount: Int {
        var count = 0
        if categoryID != nil { count += 1 }
        if labelID != nil { count += 1 }
        if kinds != Set(TransactionDraft.Kind.allCases) { count += 1 }
        if startDate != nil || endDate != nil { count += 1 }
        return count
    }

    public var isSearchActive: Bool {
        !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    public var hasAnyFeedFilter: Bool {
        activeAdvancedFilterCount > 0 || isSearchActive
    }

    public var isDateRangeActive: Bool {
        startDate != nil || endDate != nil
    }

    /// Resets the search text while preserving advanced filters, wallet, and period.
    public static func resetSearch(query: TransactionQuery) -> TransactionQuery {
        var reset = query
        reset.searchText = ""
        return reset
    }

    /// Resets advanced filters while preserving search text, wallet, and period.
    public static func resetFilters(query: TransactionQuery) -> TransactionQuery {
        var reset = query
        reset.categoryID = nil
        reset.labelID = nil
        reset.kinds = Set(TransactionDraft.Kind.allCases)
        reset.startDate = nil
        reset.endDate = nil
        return reset
    }

    /// Clears every feed-level filter while preserving wallet and period.
    public static func clearAll(query: TransactionQuery) -> TransactionQuery {
        var reset = query
        reset.searchText = ""
        reset.categoryID = nil
        reset.labelID = nil
        reset.kinds = Set(TransactionDraft.Kind.allCases)
        reset.startDate = nil
        reset.endDate = nil
        return reset
    }

    public static func apply(
        draft: TransactionQuery,
        usesDateRange: Bool,
        walletID: UUID?
    ) -> TransactionQuery {
        var applied = draft
        applied.walletID = walletID
        if !usesDateRange {
            applied.startDate = nil
            applied.endDate = nil
        } else {
            let today = DateKeys.calendar.startOfDay(for: .now)
            if applied.startDate == nil {
                applied.startDate = today
            }
            if applied.endDate == nil {
                applied.endDate = today
            }
        }
        return applied
    }

    public static func isDateRangeValid(startDate: Date?, endDate: Date?) -> Bool {
        guard let startDate, let endDate else { return true }
        return DateKeys.dayKey(for: startDate) <= DateKeys.dayKey(for: endDate)
    }
}
