import Foundation
import Testing
@testable import CashRunwayCore

@Suite(.serialized)
struct MCCCategoryMappingTests {
    @Test func mapsCommonRestaurantMCC() {
        #expect(MCCCategoryMapping.categoryName(for: 5812) == "Restaurants")
        #expect(MCCCategoryMapping.categoryName(for: 5814) == "Restaurants")
    }

    @Test func mapsCommonGroceryMCC() {
        #expect(MCCCategoryMapping.categoryName(for: 5411) == "Groceries")
        #expect(MCCCategoryMapping.categoryName(for: 5499) == "Groceries")
    }

    @Test func mapsCommonTransportMCC() {
        #expect(MCCCategoryMapping.categoryName(for: 5541) == "Transport")
        #expect(MCCCategoryMapping.categoryName(for: 5542) == "Transport")
        #expect(MCCCategoryMapping.categoryName(for: 4121) == "Transport")
    }

    @Test func mapsHealthMCC() {
        #expect(MCCCategoryMapping.categoryName(for: 5912) == "Health")
        #expect(MCCCategoryMapping.categoryName(for: 5122) == "Health")
    }

    @Test func mapsTravelMCC() {
        #expect(MCCCategoryMapping.categoryName(for: 7011) == "Travel")
    }

    @Test func returnsNilForAmbiguousReviewMCCs() {
        #expect(MCCCategoryMapping.categoryName(for: 7211) == nil)
        #expect(MCCCategoryMapping.categoryName(for: 7230) == nil)
        #expect(MCCCategoryMapping.categoryName(for: 8661) == nil)
        #expect(MCCCategoryMapping.categoryName(for: 9311) == nil)
        #expect(MCCCategoryMapping.categoryName(for: 9402) == nil)
    }

    @Test func returnsNilForBroadTravelRanges() {
        #expect(MCCCategoryMapping.categoryName(for: 3000) == nil)
        #expect(MCCCategoryMapping.categoryName(for: 3501) == nil)
        #expect(MCCCategoryMapping.categoryName(for: 4722) == nil)
    }

    @Test func returnsNilForAmbiguousFinanceMCC() {
        #expect(MCCCategoryMapping.categoryName(for: 4829) == nil)
    }

    @Test func returnsNilForUnknownMCC() {
        #expect(MCCCategoryMapping.categoryName(for: 9999) == nil)
    }
}
