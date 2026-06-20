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
    }

    @Test func mapsFinanceLabelsToUtilities() {
        #expect(BankCategoryNameMapping.categoryName(for: "Фінанси та банки", kind: .expense) == "Utilities")
        #expect(BankCategoryNameMapping.categoryName(for: "БАНКИ И ФИНАНСЫ", kind: .expense) == "Utilities")
        #expect(BankCategoryNameMapping.categoryName(for: "Кредити", kind: .expense) == "Utilities")
    }

    @Test func mapsEducationLabelsToEducation() {
        #expect(BankCategoryNameMapping.categoryName(for: "Освіта", kind: .expense) == "Education")
        #expect(BankCategoryNameMapping.categoryName(for: "Курси та навчання", kind: .expense) == "Education")
        #expect(BankCategoryNameMapping.categoryName(for: "ОБРАЗОВАНИЕ", kind: .expense) == "Education")
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

    @Test func normalizesCaseAndWhitespace() {
        #expect(BankCategoryNameMapping.categoryName(for: "  ресторани  ", kind: .expense) == "Restaurants")
        #expect(BankCategoryNameMapping.categoryName(for: "РЕСТОРАНИ", kind: .expense) == "Restaurants")
        #expect(BankCategoryNameMapping.categoryName(for: "рестораны", kind: .expense) == "Restaurants")
        #expect(BankCategoryNameMapping.categoryName(for: "Ресторани     кафе", kind: .expense) == "Restaurants")
    }

    @Test func normalizesPunctuationAndApostrophes() {
        #expect(BankCategoryNameMapping.categoryName(for: "Ресторани, кафе - бари", kind: .expense) == "Restaurants")
        #expect(BankCategoryNameMapping.categoryName(for: "Супермаркети та продукти", kind: .expense) == "Groceries")
        #expect(BankCategoryNameMapping.categoryName(for: "Комп'ютерна техніка", kind: .expense) == "Shopping")
        #expect(BankCategoryNameMapping.categoryName(for: "Комп’ютерна техніка", kind: .expense) == "Shopping")
        #expect(BankCategoryNameMapping.categoryName(for: "Фаст-фуд", kind: .expense) == "Restaurants")
        #expect(BankCategoryNameMapping.categoryName(for: "Фаст / фуд", kind: .expense) == "Restaurants")
    }

    @Test func avoidsShortTokenFalseMatches() {
        // "дом" must not match inside "невідома".
        #expect(BankCategoryNameMapping.categoryName(for: "Невідома категорія", kind: .expense) == nil)
    }
}
