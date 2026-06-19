import Foundation
import Testing
@testable import CashRunwayCore

@Suite(.serialized)
struct BankCategoryNameMappingTests {
    @Test func mapsUkrainianRestaurantCategory() {
        #expect(BankCategoryNameMapping.categoryName(for: "Ресторани, кафе, бари", kind: .expense) == "Restaurants")
    }

    @Test func mapsUkrainianGroceryCategory() {
        #expect(BankCategoryNameMapping.categoryName(for: "Супермаркети та продукти", kind: .expense) == "Groceries")
    }

    @Test func mapsUkrainianTransportCategories() {
        #expect(BankCategoryNameMapping.categoryName(for: "АЗС", kind: .expense) == "Transport")
        #expect(BankCategoryNameMapping.categoryName(for: "Таксі", kind: .expense) == "Transport")
        #expect(BankCategoryNameMapping.categoryName(for: "Авто", kind: .expense) == "Transport")
    }

    @Test func mapsUkrainianTravelCategory() {
        #expect(BankCategoryNameMapping.categoryName(for: "Квитки на поїзд", kind: .expense) == "Travel")
    }

    @Test func mapsUkrainianShoppingCategories() {
        #expect(BankCategoryNameMapping.categoryName(for: "Одяг та взуття", kind: .expense) == "Shopping")
        #expect(BankCategoryNameMapping.categoryName(for: "Цифрові товари", kind: .expense) == "Shopping")
        #expect(BankCategoryNameMapping.categoryName(for: "Краса", kind: .expense) == "Shopping")
    }

    @Test func mapsUkrainianHousingCategory() {
        #expect(BankCategoryNameMapping.categoryName(for: "Дім та ремонт", kind: .expense) == "Housing")
    }

    @Test func mapsUkrainianHealthCategory() {
        #expect(BankCategoryNameMapping.categoryName(for: "Аптеки", kind: .expense) == "Health")
        #expect(BankCategoryNameMapping.categoryName(for: "Медичні послуги", kind: .expense) == "Health")
    }

    @Test func mapsUkrainianEntertainmentCategory() {
        #expect(BankCategoryNameMapping.categoryName(for: "Спорт", kind: .expense) == "Entertainment")
    }

    @Test func mapsUkrainianServicesToOtherExpense() {
        #expect(BankCategoryNameMapping.categoryName(for: "Послуги", kind: .expense) == "Other Expense")
        #expect(BankCategoryNameMapping.categoryName(for: "Кредити", kind: .expense) == "Other Expense")
    }

    @Test func mapsUkrainianIncomeCategory() {
        #expect(BankCategoryNameMapping.categoryName(for: "Зарахування", kind: .income) == "Other Income")
        #expect(BankCategoryNameMapping.categoryName(for: "Зарахування переказу", kind: .income) == "Other Income")
    }

    @Test func returnsNilForUnknownIncomeName() {
        #expect(BankCategoryNameMapping.categoryName(for: "FooBarBaz", kind: .income) == nil)
    }

    @Test func returnsNilForUnknownName() {
        #expect(BankCategoryNameMapping.categoryName(for: "FooBarBaz", kind: .expense) == nil)
    }
}
