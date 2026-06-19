import Foundation
import Testing
@testable import CashRunwayCore

@Suite(.serialized)
struct MCCCategoryMappingTests {
    @Test func mapsCommonRestaurantMCC() {
        #expect(MCCCategoryMapping.categoryName(for: 5812) == "Restaurants")
    }

    @Test func mapsCommonGroceryMCC() {
        #expect(MCCCategoryMapping.categoryName(for: 5411) == "Groceries")
        #expect(MCCCategoryMapping.categoryName(for: 5499) == "Groceries")
    }

    @Test func mapsCommonTransportMCC() {
        #expect(MCCCategoryMapping.categoryName(for: 5541) == "Transport")
        #expect(MCCCategoryMapping.categoryName(for: 4121) == "Transport")
    }

    @Test func mapsFinanceMCCToOtherExpense() {
        #expect(MCCCategoryMapping.categoryName(for: 4829) == "Other Expense")
    }

    @Test func returnsNilForUnknownMCC() {
        #expect(MCCCategoryMapping.categoryName(for: 9999) == nil)
    }
}
