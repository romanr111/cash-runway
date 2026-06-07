import Foundation
import Testing
@testable import CashRunwayCore

@Suite(.serialized)
struct LedgerInvariantPropertyTests {

    // MARK: - Generators

    private static func randomAmount() -> Int64 {
        Int64.random(in: 1...10_000_000)
    }

    private static func randomStartingBalance() -> Int64 {
        Int64.random(in: 0...10_000_000)
    }

    // Creates a wallet with balanced start — startingBalanceMinor == currentBalanceMinor
    private static func makeWallet(
        repository: CashRunwayRepository,
        name: String
    ) throws -> Wallet {
        let balance = randomStartingBalance()
        let wallet = WalletBuilder()
            .with(name: name)
            .with(kind: .cash)
            .with(startingBalanceMinor: balance)
            .with(currentBalanceMinor: balance)
            .build()
        try repository.saveWallet(wallet)
        return wallet
    }

    // MARK: - CR-002/CR-006 Property: For any sequence of random non-transfer transactions,
    //           wallet balances and aggregates always match the raw ledger

    @Test func ledgerInvariantHoldsAfterRandomExpenseIncomeSequence() throws {
        let repository = try TestSupport.makeRepository()
        try repository.seedIfNeeded()
        let wallet = try Self.makeWallet(repository: repository, name: "Property Wallet")
        let categories = try repository.categories(kind: .expense)
        let category = categories.first

        for _ in 0..<50 {
            let draft = TransactionBuilder()
                .with(kind: Bool.random() ? .expense : .income)
                .with(walletID: wallet.id)
                .with(amountMinor: Self.randomAmount())
                .with(categoryID: category?.id)
                .build()
            try repository.saveTransaction(draft)
            try TestSupport.assertWalletTruth(repository)
            try TestSupport.assertCategoryTruth(repository)
        }
    }

    // MARK: - CR-005 Property: For any random transfer, total net worth is preserved

    @Test func transferPreservesNetWorthForAnyAmount() throws {
        let repository = try TestSupport.makeRepository()
        try repository.seedIfNeeded()
        try TestSupport.seedFixtureWallets(into: repository)
        let wallets = try repository.wallets()
        try #require(wallets.count >= 2)

        let walletA = wallets[0]
        let walletB = wallets[1]

        for _ in 0..<30 {
            let netWorthBefore = try repository.wallets().reduce(0) { $0 + $1.currentBalanceMinor }

            let draft = TransactionBuilder()
                .with(kind: .transfer)
                .with(walletID: walletA.id)
                .with(destinationWalletID: walletB.id)
                .with(amountMinor: Self.randomAmount())
                .build()
            try repository.saveTransaction(draft)

            let netWorthAfter = try repository.wallets().reduce(0) { $0 + $1.currentBalanceMinor }
            #expect(netWorthAfter == netWorthBefore)
            try TestSupport.assertWalletTruth(repository)
        }
    }

    // MARK: - CR-003/CR-004 Property: Edit and delete are reversible
    //           for random amounts on random transactions

    @Test func editAndDeleteReversibleForRandomTransactions() throws {
        let repository = try TestSupport.makeRepository()
        try repository.seedIfNeeded()
        try TestSupport.seedFixtureWallets(into: repository)
        let wallets = try repository.wallets()
        try #require(!wallets.isEmpty)

        let wallet = wallets[0]
        let categories = try repository.categories(kind: .expense)
        let category = categories.first

        for _ in 0..<25 {
            let txID = UUID()
            var draft = TransactionBuilder()
                .with(kind: Bool.random() ? .expense : .income)
                .with(walletID: wallet.id)
                .with(amountMinor: Self.randomAmount())
                .with(categoryID: category?.id)
                .build()
            draft.id = txID
            try repository.saveTransaction(draft)

            var edited = draft
            edited.amountMinor = Self.randomAmount()
            try repository.saveTransaction(edited)

            try repository.deleteTransaction(id: txID)
            try TestSupport.assertWalletTruth(repository)
        }

        let finalBalance = try repository.wallets()
            .first(where: { $0.id == wallet.id })?.currentBalanceMinor ?? 0
        #expect(finalBalance == wallet.currentBalanceMinor)
    }

    // MARK: - CR-001 Property: Multi-wallet ledger consistency
    //           under mixed random operations (transfers + expense/income + delete)

    @Test func multiWalletLedgerConsistentUnderRandomOps() throws {
        let repository = try TestSupport.makeRepository()
        try repository.seedIfNeeded()
        let walletA = try Self.makeWallet(repository: repository, name: "Alpha")
        let walletB = try Self.makeWallet(repository: repository, name: "Beta")
        let categories = try repository.categories(kind: .expense)
        let category = categories.first

        for _ in 0..<40 {
            let op = Int.random(in: 0..<4)
            switch op {
            case 0: // Expense
                let wallet = Bool.random() ? walletA : walletB
                try repository.saveTransaction(
                    TransactionBuilder()
                        .with(kind: .expense)
                        .with(walletID: wallet.id)
                        .with(amountMinor: Self.randomAmount())
                        .with(categoryID: category?.id)
                        .build()
                )

            case 1: // Income
                let wallet = Bool.random() ? walletA : walletB
                try repository.saveTransaction(
                    TransactionBuilder()
                        .with(kind: .income)
                        .with(walletID: wallet.id)
                        .with(amountMinor: Self.randomAmount())
                        .with(categoryID: category?.id)
                        .build()
                )

            case 2: // Transfer
                let draft = TransactionBuilder()
                    .with(kind: .transfer)
                    .with(walletID: walletA.id)
                    .with(destinationWalletID: walletB.id)
                    .with(amountMinor: Self.randomAmount())
                    .build()
                try repository.saveTransaction(draft)

            default: // Delete a random transaction
                let allTxs = try repository.transactions(query: .init())
                if let tx = allTxs.randomElement() {
                    try repository.deleteTransaction(id: tx.id)
                }
            }

            try TestSupport.assertWalletTruth(repository)
        }
    }
}