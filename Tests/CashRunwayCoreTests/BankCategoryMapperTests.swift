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
            merchant: "Silpo",
            description: "Cafe terminal",
            mcc: 5812,
            originalMcc: nil
        )

        #expect(resolved == groceriesID)
    }

    @Test func mccRuleWinsOverBuiltInMCCFallback() throws {
        let repository = try TestSupport.makeRepository()
        try repository.seedIfNeeded()
        let shoppingID = try categoryID(repository, named: "Shopping")
        try insertRule(repository, ruleType: "mcc", merchantPattern: nil, mcc: 5411, categoryID: shoppingID)

        let resolved = try BankCategoryMapper(repository: repository).resolve(
            merchant: nil,
            description: "Grocery terminal",
            mcc: 5411,
            originalMcc: nil
        )

        #expect(resolved == shoppingID)
    }

    @Test func builtInMCCAndOtherExpenseFallbacksResolveKnownCategories() throws {
        let repository = try TestSupport.makeRepository()
        try repository.seedIfNeeded()
        let groceriesID = try categoryID(repository, named: "Groceries")
        let otherExpenseID = try categoryID(repository, named: "Other Expense")
        let mapper = BankCategoryMapper(repository: repository)

        let builtIn = try mapper.resolve(merchant: nil, description: "Food shop", mcc: 5411, originalMcc: nil)
        let fallback = try mapper.resolve(merchant: nil, description: "Unknown", mcc: 9999, originalMcc: nil)

        #expect(builtIn == groceriesID)
        #expect(fallback == otherExpenseID)
    }

    @Test func originalMCCFallsBackToBuiltInCategoryWhenPrimaryMCCIsUnknown() throws {
        let repository = try TestSupport.makeRepository()
        try repository.seedIfNeeded()
        let groceriesID = try categoryID(repository, named: "Groceries")

        let resolved = try BankCategoryMapper(repository: repository).resolve(
            merchant: nil,
            description: "Fallback category",
            mcc: 9999,
            originalMcc: 5411
        )

        #expect(resolved == groceriesID)
    }

    private func categoryID(_ repository: CashRunwayRepository, named name: String) throws -> UUID {
        try #require(try repository.categories(kind: .expense).first { $0.name == name }?.id)
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
