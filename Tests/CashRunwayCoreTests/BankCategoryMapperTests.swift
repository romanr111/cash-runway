import Foundation
import GRDB
import Testing
@testable import CashRunwayCore

@Suite(.serialized)
struct BankCategoryMapperTests {
    @Test func merchantRuleWinsOverMCCFallback() throws {
        let repository = try TestSupport.makeRepository()
        try repository.seedIfNeeded()
        let groceriesID = try categoryID(repository, named: "Groceries")
        let restaurantsID = try categoryID(repository, named: "Restaurants")
        try insertRule(repository, ruleType: "merchant", merchantPattern: "silpo", mcc: nil, categoryID: groceriesID)
        try insertRule(repository, ruleType: "mcc", merchantPattern: nil, mcc: 5812, categoryID: restaurantsID)

        let resolved = try BankCategoryMapper(repository: repository).resolve(
            source: .bankStatement(.monobank),
            kind: .expense,
            merchant: "Silpo",
            description: "Cafe terminal",
            rawCategoryName: nil,
            mcc: 5812,
            originalMcc: nil
        )

        #expect(resolved?.categoryID == groceriesID)
    }

    @Test func mccRuleWinsOverBuiltInMCCFallback() throws {
        let repository = try TestSupport.makeRepository()
        try repository.seedIfNeeded()
        let shoppingID = try categoryID(repository, named: "Shopping")
        try insertRule(repository, ruleType: "mcc", merchantPattern: nil, mcc: 5411, categoryID: shoppingID)

        let resolved = try BankCategoryMapper(repository: repository).resolve(
            source: .bankStatement(.monobank),
            kind: .expense,
            merchant: nil,
            description: "Grocery terminal",
            rawCategoryName: nil,
            mcc: 5411,
            originalMcc: nil
        )

        #expect(resolved?.categoryID == shoppingID)
    }

    @Test func builtInMCCAndOtherExpenseFallbacksResolveKnownCategories() throws {
        let repository = try TestSupport.makeRepository()
        try repository.seedIfNeeded()
        let groceriesID = try categoryID(repository, named: "Groceries")
        let otherExpenseID = try categoryID(repository, named: "Other Expense")
        let mapper = try BankCategoryMapper(repository: repository)

        let builtIn = mapper.resolve(
            source: .bankStatement(.monobank),
            kind: .expense,
            merchant: nil,
            description: "Food shop",
            rawCategoryName: nil,
            mcc: 5411,
            originalMcc: nil
        )
        let fallback = mapper.resolve(
            source: .bankStatement(.monobank),
            kind: .expense,
            merchant: nil,
            description: "Unknown",
            rawCategoryName: nil,
            mcc: 9999,
            originalMcc: nil
        )

        #expect(builtIn?.categoryID == groceriesID)
        #expect(fallback?.categoryID == otherExpenseID)
    }

    @Test func builtInMCCFallbackUsesMergedDestinationCategory() throws {
        let repository = try TestSupport.makeRepository()
        try repository.seedIfNeeded()
        let groceriesID = try categoryID(repository, named: "Groceries")
        let restaurantsID = try categoryID(repository, named: "Restaurants")

        try repository.mergeCategory(oldCategoryID: restaurantsID, into: groceriesID)

        let resolved = try BankCategoryMapper(repository: repository).resolve(
            source: .bankStatement(.monobank),
            kind: .expense,
            merchant: nil,
            description: "Food shop",
            rawCategoryName: nil,
            mcc: 5812,
            originalMcc: nil
        )

        #expect(resolved?.categoryID == groceriesID)
        #expect(try repository.categories(kind: .expense).contains { $0.id == restaurantsID } == false)
    }

    @Test func builtInMCCFallbackFollowsChainedMergedDestinationCategory() throws {
        let repository = try TestSupport.makeRepository()
        try repository.seedIfNeeded()
        let shoppingID = try categoryID(repository, named: "Shopping")
        let groceriesID = try categoryID(repository, named: "Groceries")
        let restaurantsID = try categoryID(repository, named: "Restaurants")

        try repository.mergeCategory(oldCategoryID: restaurantsID, into: groceriesID)
        try repository.mergeCategory(oldCategoryID: groceriesID, into: shoppingID)

        let resolved = try BankCategoryMapper(repository: repository).resolve(
            source: .bankStatement(.monobank),
            kind: .expense,
            merchant: nil,
            description: "Food shop",
            rawCategoryName: nil,
            mcc: 5812,
            originalMcc: nil
        )

        #expect(resolved?.categoryID == shoppingID)
    }

    @Test func originalMCCFallsBackToBuiltInCategoryWhenPrimaryMCCIsUnknown() throws {
        let repository = try TestSupport.makeRepository()
        try repository.seedIfNeeded()
        let groceriesID = try categoryID(repository, named: "Groceries")

        let resolved = try BankCategoryMapper(repository: repository).resolve(
            source: .bankStatement(.monobank),
            kind: .expense,
            merchant: nil,
            description: "Fallback category",
            rawCategoryName: nil,
            mcc: 9999,
            originalMcc: 5411
        )

        #expect(resolved?.categoryID == groceriesID)
    }

    @Test func ukrainianCategoryAliasFallsBackToMCCWhenUnknown() throws {
        let repository = try TestSupport.makeRepository()
        try repository.seedIfNeeded()
        let groceriesID = try categoryID(repository, named: "Groceries")

        let resolved = try BankCategoryMapper(repository: repository).resolve(
            source: .bankStatement(.privatBank),
            kind: .expense,
            merchant: "Unknown shop",
            description: "Unknown shop",
            rawCategoryName: "Невідома категорія",
            mcc: 5411,
            originalMcc: nil
        )

        #expect(resolved?.categoryID == groceriesID)
    }

    @Test func existingCategoryWinsOverUkrainianAlias() throws {
        let repository = try TestSupport.makeRepository()
        try repository.seedIfNeeded()
        let customID = try createCategory(repository, name: "Ресторани", kind: .expense)

        let resolved = try BankCategoryMapper(repository: repository).resolve(
            source: .bankStatement(.privatBank),
            kind: .expense,
            merchant: "Some place",
            description: "Some place",
            rawCategoryName: "Ресторани",
            mcc: 5411,
            originalMcc: nil
        )

        #expect(resolved?.categoryID == customID)
    }

    @Test func merchantRuleRunsEvenWhenMCCIsAbsent() throws {
        let repository = try TestSupport.makeRepository()
        try repository.seedIfNeeded()
        let transportID = try categoryID(repository, named: "Transport")
        try insertRule(repository, ruleType: "merchant", merchantPattern: "uber", mcc: nil, categoryID: transportID)

        let resolved = try BankCategoryMapper(repository: repository).resolve(
            source: .bankStatement(.monobank),
            kind: .expense,
            merchant: "uber trip",
            description: "uber trip",
            rawCategoryName: "Транспорт",
            mcc: nil,
            originalMcc: nil
        )

        #expect(resolved?.categoryID == transportID)
    }

    @Test func cashRunwayWalletIgnoresMCCAndBankAliases() throws {
        let repository = try TestSupport.makeRepository()
        try repository.seedIfNeeded()
        let customID = try createCategory(repository, name: "Продукти", kind: .expense)

        let resolved = try BankCategoryMapper(repository: repository).resolve(
            source: .cashRunwayWallet,
            kind: .expense,
            merchant: "Сільпо",
            description: "Сільпо",
            rawCategoryName: "Продукти",
            mcc: 5411,
            originalMcc: nil
        )

        #expect(resolved?.categoryID == customID)
    }

    @Test func exactMatchRespectsTransactionKind() throws {
        let repository = try TestSupport.makeRepository()
        try repository.seedIfNeeded()
        // "Зарплата" exists as an income category. An expense row with the same
        // name must not resolve to the income category.
        let resolved = try BankCategoryMapper(repository: repository).resolve(
            source: .bankStatement(.privatBank),
            kind: .expense,
            merchant: "Employer",
            description: "Employer",
            rawCategoryName: "Зарплата",
            mcc: nil,
            originalMcc: nil
        )

        let salaryID = try #require(try repository.categories(kind: .income).first { $0.name == "Salary" }?.id)
        #expect(resolved?.categoryID != salaryID)
        let otherExpenseID = try categoryID(repository, named: "Other Expense")
        #expect(resolved?.categoryID == otherExpenseID)
    }

    @Test func incomeRowRetainsIncomeFallback() throws {
        let repository = try TestSupport.makeRepository()
        try repository.seedIfNeeded()
        let otherIncomeID = try #require(try repository.categories(kind: .income).first { $0.name == "Other Income" }?.id)

        let resolved = try BankCategoryMapper(repository: repository).resolve(
            source: .bankStatement(.privatBank),
            kind: .income,
            merchant: "Unknown",
            description: "Unknown",
            rawCategoryName: "Невідомий дохід",
            mcc: 5411,
            originalMcc: nil
        )

        #expect(resolved?.categoryID == otherIncomeID)
    }

    @Test func temuMerchantOverridesBankHousingCategory() throws {
        let repository = try TestSupport.makeRepository()
        try repository.seedIfNeeded()

        let shoppingID = try categoryID(repository, named: "Shopping")

        let resolved = try BankCategoryMapper(repository: repository).resolve(
            source: .bankStatement(.privatBank),
            kind: .expense,
            merchant: "Temu",
            description: "Temu",
            rawCategoryName: "Житло",
            mcc: nil,
            originalMcc: nil
        )

        #expect(resolved?.categoryID == shoppingID)
    }

    private func categoryID(_ repository: CashRunwayRepository, named name: String) throws -> UUID {
        try #require(try repository.categories(kind: .expense).first { $0.name == name }?.id)
    }

    private func createCategory(_ repository: CashRunwayRepository, name: String, kind: CategoryKind) throws -> UUID {
        let id = UUID()
        try repository.databaseManager.dbQueue.write { db in
            try db.execute(
                sql: """
                INSERT INTO categories (id, name, kind, icon_name, color_hex, parent_id, is_system, is_archived, sort_order, created_at, updated_at)
                VALUES (?, ?, ?, ?, ?, NULL, 0, 0, 0, ?, ?)
                """,
                arguments: [id.uuidString, name, kind.rawValue, "questionmark.circle.fill", "#60788A", Date(), Date()]
            )
        }
        return id
    }

    private func insertRule(
        _ repository: CashRunwayRepository,
        ruleType: String,
        merchantPattern: String?,
        mcc: Int?,
        categoryID: UUID
    ) throws {
        try repository.databaseManager.dbQueue.write { db in
            try db.execute(
                sql: """
                INSERT INTO bank_category_rules (
                    id, provider, rule_type, merchant_pattern, mcc, category_id, confidence, created_at, updated_at
                )
                VALUES (?, ?, ?, ?, ?, ?, 100, ?, ?)
                """,
                arguments: [
                    UUID().uuidString,
                    BankProvider.monobank.rawValue,
                    ruleType,
                    merchantPattern,
                    mcc,
                    categoryID.uuidString,
                    Date(timeIntervalSince1970: 1_800_000_000),
                    Date(timeIntervalSince1970: 1_800_000_000),
                ]
            )
        }
    }
}
