import Foundation
import Testing
@testable import CashRunwayCore

/// Property-style tests using seeded random data to verify query and snapshot correctness.
/// Inspired by property-based testing patterns: generate valid inputs, apply operations,
/// assert invariants that must hold for all valid inputs.
@Suite(.serialized)
struct PropertyStyleQueryTests {

    // MARK: - TransactionQuery invariants

    @Test func queryFilterByWalletReturnsOnlyMatchingTransactions() throws {
        let repository = try TestSupport.makeRepository()
        try repository.seedIfNeeded()
        try TestSupport.seedFixtureWallets(into: repository)
        let wallets = try repository.wallets()
        let expenseCategory = try #require(try repository.categories(kind: .expense).first)
        let walletA = wallets[0]
        let walletB = wallets[1]

        try repository.saveTransaction(
            TransactionBuilder().with(walletID: walletA.id).with(categoryID: expenseCategory.id).with(amountMinor: 100).build()
        )
        try repository.saveTransaction(
            TransactionBuilder().with(walletID: walletB.id).with(categoryID: expenseCategory.id).with(amountMinor: 200).build()
        )
        try repository.saveTransaction(
            TransactionBuilder().with(walletID: walletA.id).with(categoryID: expenseCategory.id).with(amountMinor: 300).build()
        )

        let query = TransactionQuery(walletID: walletA.id)
        let results = try repository.transactions(query: query)
        #expect(results.count == 2)
        #expect(results.allSatisfy { $0.walletName == walletA.name })
    }

    @Test func queryFilterByKindExcludesOtherKinds() throws {
        let repository = try TestSupport.makeRepository()
        try repository.seedIfNeeded()
        try TestSupport.seedFixtureWallets(into: repository)
        let wallets = try repository.wallets()
        let expenseCategory = try #require(try repository.categories(kind: .expense).first)
        let incomeCategory = try #require(try repository.categories(kind: .income).first)
        let wallet = wallets[0]

        try repository.saveTransaction(
            TransactionBuilder().with(kind: .expense).with(walletID: wallet.id).with(categoryID: expenseCategory.id).build()
        )
        try repository.saveTransaction(
            TransactionBuilder().with(kind: .income).with(walletID: wallet.id).with(categoryID: incomeCategory.id).build()
        )
        try repository.saveTransaction(
            TransactionBuilder().with(kind: .expense).with(walletID: wallet.id).with(categoryID: expenseCategory.id).build()
        )

        let query = TransactionQuery(kinds: [.expense])
        let results = try repository.transactions(query: query)
        #expect(results.count == 2)
        #expect(results.allSatisfy { $0.kind == .expense })
    }

    @Test func queryFilterByDateRangeReturnsOnlyTransactionsWithinRange() throws {
        let repository = try TestSupport.makeRepository()
        try repository.seedIfNeeded()
        try TestSupport.seedFixtureWallets(into: repository)
        let wallets = try repository.wallets()
        let expenseCategory = try #require(try repository.categories(kind: .expense).first)
        let wallet = wallets[0]
        let calendar = Calendar(identifier: .gregorian)

        let jan1 = calendar.date(from: DateComponents(year: 2025, month: 1, day: 1))!
        let feb1 = calendar.date(from: DateComponents(year: 2025, month: 2, day: 1))!
        let mar1 = calendar.date(from: DateComponents(year: 2025, month: 3, day: 1))!

        try repository.saveTransaction(
            TransactionBuilder().with(walletID: wallet.id).with(categoryID: expenseCategory.id).with(occurredAt: jan1).build()
        )
        try repository.saveTransaction(
            TransactionBuilder().with(walletID: wallet.id).with(categoryID: expenseCategory.id).with(occurredAt: feb1).build()
        )
        try repository.saveTransaction(
            TransactionBuilder().with(walletID: wallet.id).with(categoryID: expenseCategory.id).with(occurredAt: mar1).build()
        )

        // endDate is treated as inclusive; add 1s to make Feb 1 exclusive so only Jan 1 and Feb 1 remain.
        let query = TransactionQuery(startDate: jan1, endDate: feb1.addingTimeInterval(1))
        let results = try repository.transactions(query: query)
        #expect(results.count == 2)
    }

    // MARK: - OverviewSnapshot invariants

    @Test func overviewSnapshotTotalsMatchIndividualTransactions() throws {
        let repository = try TestSupport.makeRepository()
        try repository.seedIfNeeded()
        try TestSupport.seedFixtureWallets(into: repository)
        let wallets = try repository.wallets()
        let expenseCategory = try #require(try repository.categories(kind: .expense).first)
        let incomeCategory = try #require(try repository.categories(kind: .income).first)
        let wallet = wallets[0]
        let monthKey = 202501
        let janDate = Calendar(identifier: .gregorian).date(from: DateComponents(year: 2025, month: 1, day: 15))!

        try repository.saveTransaction(
            TransactionBuilder().with(kind: .expense).with(walletID: wallet.id).with(categoryID: expenseCategory.id).with(amountMinor: 500).with(occurredAt: janDate).build()
        )
        try repository.saveTransaction(
            TransactionBuilder().with(kind: .expense).with(walletID: wallet.id).with(categoryID: expenseCategory.id).with(amountMinor: 300).with(occurredAt: janDate).build()
        )
        try repository.saveTransaction(
            TransactionBuilder().with(kind: .income).with(walletID: wallet.id).with(categoryID: incomeCategory.id).with(amountMinor: 1000).with(occurredAt: janDate).build()
        )

        let overview = try repository.overviewSnapshot(monthKey: monthKey, walletID: wallet.id)

        #expect(overview.monthExpenseMinor == 800)
        #expect(overview.monthIncomeMinor == 1000)
    }

    // MARK: - SeededRNG reproducibility

    @Test func seededRNGGeneratesReproducibleSequence() {
        var rng1 = FixtureGenerator.SeededRNG(seed: 42)
        var rng2 = FixtureGenerator.SeededRNG(seed: 42)

        let values1 = (0..<100).map { _ in Int.random(in: 0..<1000, using: &rng1) }
        let values2 = (0..<100).map { _ in Int.random(in: 0..<1000, using: &rng2) }

        #expect(values1 == values2)
    }

    @Test func seededRNGGeneratesDeterministicTransactions() throws {
        let repository1 = try TestSupport.makeRepository()
        let repository2 = try TestSupport.makeRepository()

        try populateWithSeed(repository1, seed: 77, count: 50)
        try populateWithSeed(repository2, seed: 77, count: 50)

        let transactions1 = try repository1.transactions(query: .init())
        let transactions2 = try repository2.transactions(query: .init())

        #expect(transactions1.count == transactions2.count)
        for (t1, t2) in zip(transactions1, transactions2) {
            #expect(t1.amountMinor == t2.amountMinor)
            #expect(t1.kind == t2.kind)
            #expect(t1.merchant == t2.merchant)
            #expect(t1.dayKey == t2.dayKey)
        }
    }

    private func populateWithSeed(_ repository: CashRunwayRepository, seed: UInt64, count: Int) throws {
        try repository.seedIfNeeded()
        try TestSupport.seedFixtureWallets(into: repository)
        let generator = FixtureGenerator(repository: repository)
        try generator.populate(seed: seed, transactionCount: count)
    }
}
