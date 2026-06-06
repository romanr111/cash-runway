import Foundation
import Testing
@testable import CashRunwayCore

@Suite(.serialized)
struct CategoryIntegrityTests {

    // MARK: - Helpers

    private func makeRepository() throws -> CashRunwayRepository {
        let repository = try TestSupport.makeRepository()
        try repository.seedIfNeeded()
        return repository
    }

    private func makeWallet(repository: CashRunwayRepository, name: String, balanceMinor: Int64) throws -> Wallet {
        let wallet = WalletBuilder()
            .with(name: name)
            .with(kind: .cash)
            .with(startingBalanceMinor: balanceMinor)
            .with(currentBalanceMinor: balanceMinor)
            .build()
        try repository.saveWallet(wallet)
        return wallet
    }

    // MARK: - CR-007: Category merge preserves transaction count and totals

    @Test func categoryMergePreservesTransactionCountAndTotal() throws {
        let repository = try makeRepository()
        let wallet = try makeWallet(repository: repository, name: "Cash", balanceMinor: 1_000_000)

        let oldCategory = CategoryBuilder().with(name: "Old Category").with(kind: .expense).build()
        let newCategory = CategoryBuilder().with(name: "New Category").with(kind: .expense).build()
        try repository.saveCategory(oldCategory)
        try repository.saveCategory(newCategory)

        let now = Date()
        let tx1 = TransactionBuilder()
            .with(kind: .expense)
            .with(walletID: wallet.id)
            .with(categoryID: oldCategory.id)
            .with(amountMinor: 10_000)
            .with(occurredAt: now)
            .with(merchant: "M1")
            .build()
        let tx2 = TransactionBuilder()
            .with(kind: .expense)
            .with(walletID: wallet.id)
            .with(categoryID: oldCategory.id)
            .with(amountMinor: 20_000)
            .with(occurredAt: now)
            .with(merchant: "M2")
            .build()
        let tx3 = TransactionBuilder()
            .with(kind: .expense)
            .with(walletID: wallet.id)
            .with(categoryID: newCategory.id)
            .with(amountMinor: 30_000)
            .with(occurredAt: now)
            .with(merchant: "M3")
            .build()

        try repository.saveTransaction(tx1)
        try repository.saveTransaction(tx2)
        try repository.saveTransaction(tx3)

        try repository.mergeCategory(oldCategoryID: oldCategory.id, into: newCategory.id)

        let mergedTransactions = try repository.transactions(query: TransactionQuery(categoryID: newCategory.id))
        #expect(mergedTransactions.count == 3)

        let totalAmount = mergedTransactions.reduce(0) { $0 + abs($1.amountMinor) }
        #expect(totalAmount == 60_000)
    }

    @Test func categoryMergeChangesOnlyCategoryReferences() throws {
        let repository = try makeRepository()
        let wallet = try makeWallet(repository: repository, name: "Cash", balanceMinor: 1_000_000)

        let oldCategory = CategoryBuilder().with(name: "Old Category").with(kind: .expense).build()
        let newCategory = CategoryBuilder().with(name: "New Category").with(kind: .expense).build()
        try repository.saveCategory(oldCategory)
        try repository.saveCategory(newCategory)

        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let txID = UUID()
        var draft = TransactionBuilder()
            .with(kind: .expense)
            .with(walletID: wallet.id)
            .with(categoryID: oldCategory.id)
            .with(amountMinor: 15_000)
            .with(occurredAt: now)
            .with(merchant: "Coffee")
            .with(note: "Morning brew")
            .build()
        draft.id = txID
        try repository.saveTransaction(draft)

        try repository.mergeCategory(oldCategoryID: oldCategory.id, into: newCategory.id)

        let retrieved = try repository.transactionDraft(id: txID)
        #expect(retrieved.categoryID == newCategory.id)
        #expect(retrieved.amountMinor == 15_000)
        #expect(retrieved.walletID == wallet.id)
        #expect(retrieved.occurredAt == now)
        #expect(retrieved.merchant == "Coffee")
        #expect(retrieved.note == "Morning brew")
    }

    @Test func categoryMergeDoesNotMutateTransactionIdentityAmountDateOrWallet() throws {
        let repository = try makeRepository()
        let walletA = try makeWallet(repository: repository, name: "A", balanceMinor: 500_000)
        let walletB = try makeWallet(repository: repository, name: "B", balanceMinor: 300_000)

        let oldCategory = CategoryBuilder().with(name: "Old").with(kind: .expense).build()
        let newCategory = CategoryBuilder().with(name: "New").with(kind: .expense).build()
        try repository.saveCategory(oldCategory)
        try repository.saveCategory(newCategory)

        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let txID = UUID()
        var draft = TransactionBuilder()
            .with(kind: .expense)
            .with(walletID: walletA.id)
            .with(categoryID: oldCategory.id)
            .with(amountMinor: 42_000)
            .with(occurredAt: now)
            .with(merchant: "Store")
            .build()
        draft.id = txID
        try repository.saveTransaction(draft)

        let balanceBefore = walletA.currentBalanceMinor - 42_000
        #expect(try repository.wallets().first { $0.id == walletA.id }?.currentBalanceMinor == balanceBefore)

        try repository.mergeCategory(oldCategoryID: oldCategory.id, into: newCategory.id)

        let retrieved = try repository.transactionDraft(id: txID)
        #expect(retrieved.id == txID)
        #expect(retrieved.amountMinor == 42_000)
        #expect(retrieved.walletID == walletA.id)
        #expect(retrieved.occurredAt == now)
        #expect(retrieved.merchant == "Store")
        #expect(try repository.wallets().first { $0.id == walletA.id }?.currentBalanceMinor == balanceBefore)
        #expect(try repository.wallets().first { $0.id == walletB.id }?.currentBalanceMinor == 300_000)
    }

    // MARK: - CR-008: Category merge leaves no orphan references

    @Test func categoryMergeLeavesNoOrphanCategoryReferences() throws {
        let repository = try makeRepository()
        let wallet = try makeWallet(repository: repository, name: "Cash", balanceMinor: 1_000_000)

        let oldCategory = CategoryBuilder().with(name: "Old").with(kind: .expense).build()
        let newCategory = CategoryBuilder().with(name: "New").with(kind: .expense).build()
        try repository.saveCategory(oldCategory)
        try repository.saveCategory(newCategory)

        let now = Date()
        let tx1 = TransactionBuilder()
            .with(kind: .expense)
            .with(walletID: wallet.id)
            .with(categoryID: oldCategory.id)
            .with(amountMinor: 10_000)
            .with(occurredAt: now)
            .build()
        let tx2 = TransactionBuilder()
            .with(kind: .expense)
            .with(walletID: wallet.id)
            .with(categoryID: oldCategory.id)
            .with(amountMinor: 20_000)
            .with(occurredAt: now)
            .build()

        try repository.saveTransaction(tx1)
        try repository.saveTransaction(tx2)

        try repository.mergeCategory(oldCategoryID: oldCategory.id, into: newCategory.id)

        let orphans = try repository.transactions(query: TransactionQuery(categoryID: oldCategory.id))
        #expect(orphans.isEmpty, "No transactions should reference the old category after merge.")

        let underNew = try repository.transactions(query: TransactionQuery(categoryID: newCategory.id))
        #expect(underNew.count == 2)
    }
}
