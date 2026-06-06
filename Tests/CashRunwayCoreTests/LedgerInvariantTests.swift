import Foundation
import Testing
@testable import CashRunwayCore

@Suite(.serialized)
struct LedgerInvariantTests {

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

    private func walletBalance(repository: CashRunwayRepository, id: UUID) throws -> Int64 {
        try repository.wallets().first { $0.id == id }?.currentBalanceMinor ?? 0
    }

    private func totalNetWorth(repository: CashRunwayRepository) throws -> Int64 {
        try repository.wallets().reduce(0) { $0 + $1.currentBalanceMinor }
    }

    // MARK: - CR-002: Create transaction preserves ledger correctness

    @Test func expenseDecreasesWalletBalance() throws {
        let repository = try makeRepository()
        let wallet = try makeWallet(repository: repository, name: "Cash", balanceMinor: 100_000)
        let category = try #require(try repository.categories(kind: .expense).first)

        let draft = TransactionBuilder()
            .with(kind: .expense)
            .with(walletID: wallet.id)
            .with(categoryID: category.id)
            .with(amountMinor: 30_000)
            .build()
        try repository.saveTransaction(draft)

        #expect(try walletBalance(repository: repository, id: wallet.id) == 70_000)
    }

    @Test func incomeIncreasesWalletBalance() throws {
        let repository = try makeRepository()
        let wallet = try makeWallet(repository: repository, name: "Cash", balanceMinor: 100_000)
        let category = try #require(try repository.categories(kind: .income).first)

        let draft = TransactionBuilder()
            .with(kind: .income)
            .with(walletID: wallet.id)
            .with(categoryID: category.id)
            .with(amountMinor: 50_000)
            .build()
        try repository.saveTransaction(draft)

        #expect(try walletBalance(repository: repository, id: wallet.id) == 150_000)
    }

    // MARK: - CR-003: Edit transaction recalculates derived values

    @Test func editingTransactionAmountRecalculatesBalance() throws {
        let repository = try makeRepository()
        let wallet = try makeWallet(repository: repository, name: "Cash", balanceMinor: 100_000)
        let category = try #require(try repository.categories(kind: .expense).first)
        let txID = UUID()

        var draft = TransactionBuilder()
            .with(kind: .expense)
            .with(walletID: wallet.id)
            .with(categoryID: category.id)
            .with(amountMinor: 30_000)
            .build()
        draft.id = txID
        try repository.saveTransaction(draft)
        #expect(try walletBalance(repository: repository, id: wallet.id) == 70_000)

        var edited = draft
        edited.amountMinor = 20_000
        try repository.saveTransaction(edited)
        #expect(try walletBalance(repository: repository, id: wallet.id) == 80_000)
    }

    @Test func editingTransactionWalletRecalculatesBothBalances() throws {
        let repository = try makeRepository()
        let walletA = try makeWallet(repository: repository, name: "A", balanceMinor: 100_000)
        let walletB = try makeWallet(repository: repository, name: "B", balanceMinor: 50_000)
        let category = try #require(try repository.categories(kind: .expense).first)
        let txID = UUID()

        var draft = TransactionBuilder()
            .with(kind: .expense)
            .with(walletID: walletA.id)
            .with(categoryID: category.id)
            .with(amountMinor: 30_000)
            .build()
        draft.id = txID
        try repository.saveTransaction(draft)
        #expect(try walletBalance(repository: repository, id: walletA.id) == 70_000)
        #expect(try walletBalance(repository: repository, id: walletB.id) == 50_000)

        var edited = draft
        edited.walletID = walletB.id
        try repository.saveTransaction(edited)
        #expect(try walletBalance(repository: repository, id: walletA.id) == 100_000)
        #expect(try walletBalance(repository: repository, id: walletB.id) == 20_000)
    }

    // MARK: - CR-004: Delete transaction removes its ledger effect

    @Test func deletingTransactionRestoresBalance() throws {
        let repository = try makeRepository()
        let wallet = try makeWallet(repository: repository, name: "Cash", balanceMinor: 100_000)
        let category = try #require(try repository.categories(kind: .expense).first)
        let txID = UUID()

        var draft = TransactionBuilder()
            .with(kind: .expense)
            .with(walletID: wallet.id)
            .with(categoryID: category.id)
            .with(amountMinor: 30_000)
            .build()
        draft.id = txID
        try repository.saveTransaction(draft)
        #expect(try walletBalance(repository: repository, id: wallet.id) == 70_000)

        try repository.deleteTransaction(id: txID)
        #expect(try walletBalance(repository: repository, id: wallet.id) == 100_000)
    }

    // MARK: - CR-005: Transfer preserves total net worth

    @Test func transferMovesValueAndPreservesNetWorth() throws {
        let repository = try makeRepository()
        let walletA = try makeWallet(repository: repository, name: "A", balanceMinor: 100_000)
        let walletB = try makeWallet(repository: repository, name: "B", balanceMinor: 50_000)

        let draft = TransactionBuilder()
            .with(kind: .transfer)
            .with(walletID: walletA.id)
            .with(destinationWalletID: walletB.id)
            .with(amountMinor: 30_000)
            .build()
        try repository.saveTransaction(draft)

        #expect(try walletBalance(repository: repository, id: walletA.id) == 70_000)
        #expect(try walletBalance(repository: repository, id: walletB.id) == 80_000)
        #expect(try totalNetWorth(repository: repository) == 150_000)
    }

    @Test func deletingTransferRestoresBothBalances() throws {
        let repository = try makeRepository()
        let walletA = try makeWallet(repository: repository, name: "A", balanceMinor: 100_000)
        let walletB = try makeWallet(repository: repository, name: "B", balanceMinor: 50_000)
        let txID = UUID()

        var draft = TransactionBuilder()
            .with(kind: .transfer)
            .with(walletID: walletA.id)
            .with(destinationWalletID: walletB.id)
            .with(amountMinor: 30_000)
            .build()
        draft.id = txID
        try repository.saveTransaction(draft)

        try repository.deleteTransaction(id: txID)

        #expect(try walletBalance(repository: repository, id: walletA.id) == 100_000)
        #expect(try walletBalance(repository: repository, id: walletB.id) == 50_000)
        #expect(try totalNetWorth(repository: repository) == 150_000)
    }

    // MARK: - CR-006: Aggregate/dashboard summary matches raw transaction ledger

    @Test func dashboardMatchesRawLedgerAfterOperations() throws {
        let repository = try makeRepository()
        let wallet = try makeWallet(repository: repository, name: "Cash", balanceMinor: 1_000_000)
        let expenseCategory = try #require(try repository.categories(kind: .expense).first)
        let incomeCategory = try #require(try repository.categories(kind: .income).first)
        let now = Date()
        let monthKey = DateKeys.monthKey(for: now)

        let incomeDraft = TransactionBuilder()
            .with(kind: .income)
            .with(walletID: wallet.id)
            .with(categoryID: incomeCategory.id)
            .with(amountMinor: 100_000)
            .with(occurredAt: now)
            .build()
        try repository.saveTransaction(incomeDraft)

        let expenseDraft = TransactionBuilder()
            .with(kind: .expense)
            .with(walletID: wallet.id)
            .with(categoryID: expenseCategory.id)
            .with(amountMinor: 30_000)
            .with(occurredAt: now)
            .build()
        try repository.saveTransaction(expenseDraft)

        let dashboard = try repository.dashboard(monthKey: monthKey)
        let allTransactions = try repository.transactions(query: .init())

        let expectedTotalBalance = try totalNetWorth(repository: repository)
        let expectedIncome = allTransactions.filter { $0.kind == .income }.reduce(0) { $0 + $1.amountMinor }
        let expectedExpense = allTransactions.filter { $0.kind == .expense }.reduce(0) { $0 + abs($1.amountMinor) }

        #expect(dashboard.totalBalanceMinor == expectedTotalBalance)
        #expect(dashboard.monthIncomeMinor == expectedIncome)
        #expect(dashboard.monthExpenseMinor == expectedExpense)
        #expect(dashboard.monthNetMinor == expectedIncome - expectedExpense)
    }

    @Test func dashboardRecomputesCorrectlyAfterEditAndDelete() throws {
        let repository = try makeRepository()
        let wallet = try makeWallet(repository: repository, name: "Cash", balanceMinor: 500_000)
        let expenseCategory = try #require(try repository.categories(kind: .expense).first)
        let now = Date()
        let monthKey = DateKeys.monthKey(for: now)

        let txID = UUID()
        var draft = TransactionBuilder()
            .with(kind: .expense)
            .with(walletID: wallet.id)
            .with(categoryID: expenseCategory.id)
            .with(amountMinor: 50_000)
            .with(occurredAt: now)
            .build()
        draft.id = txID
        try repository.saveTransaction(draft)

        var edited = draft
        edited.amountMinor = 20_000
        try repository.saveTransaction(edited)

        let dashboardAfterEdit = try repository.dashboard(monthKey: monthKey)
        #expect(dashboardAfterEdit.monthExpenseMinor == 20_000)
        #expect(try walletBalance(repository: repository, id: wallet.id) == 480_000)

        try repository.deleteTransaction(id: txID)

        let dashboardAfterDelete = try repository.dashboard(monthKey: monthKey)
        #expect(dashboardAfterDelete.monthExpenseMinor == 0)
        #expect(try walletBalance(repository: repository, id: wallet.id) == 500_000)
    }

    // MARK: - CR-001: Wallet balances match transaction ledger

    @Test func walletBalancesMatchTransactionLedgerSum() throws {
        let repository = try makeRepository()
        let wallet = try makeWallet(repository: repository, name: "Cash", balanceMinor: 200_000)
        let expenseCategory = try #require(try repository.categories(kind: .expense).first)
        let incomeCategory = try #require(try repository.categories(kind: .income).first)
        let now = Date()

        try repository.saveTransaction(
            TransactionBuilder()
                .with(kind: .income)
                .with(walletID: wallet.id)
                .with(categoryID: incomeCategory.id)
                .with(amountMinor: 100_000)
                .with(occurredAt: now)
                .build()
        )

        try repository.saveTransaction(
            TransactionBuilder()
                .with(kind: .expense)
                .with(walletID: wallet.id)
                .with(categoryID: expenseCategory.id)
                .with(amountMinor: 40_000)
                .with(occurredAt: now)
                .build()
        )

        try repository.saveTransaction(
            TransactionBuilder()
                .with(kind: .expense)
                .with(walletID: wallet.id)
                .with(categoryID: expenseCategory.id)
                .with(amountMinor: 10_000)
                .with(occurredAt: now)
                .build()
        )

        let expectedBalance = 200_000 + 100_000 - 40_000 - 10_000
        #expect(try walletBalance(repository: repository, id: wallet.id) == expectedBalance)
        #expect(try totalNetWorth(repository: repository) == expectedBalance)
    }
}
