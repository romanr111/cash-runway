import Foundation
import GRDB
import Testing
@testable import CashRunwayCore

@Suite(.serialized)
struct WalletCategoryTests {
    @Test func builtInWalletCategoriesAreAvailable() throws {
        let repository = try TestSupport.makeRepository()
        try repository.seedIfNeeded()

        let categories = try repository.walletCategories()
        let kinds = Set(categories.map(\.kind))

        #expect(kinds.contains(.cash))
        #expect(kinds.contains(.card))
        #expect(kinds.contains(.account))
        #expect(kinds.contains(.other))
        #expect(categories.filter(\.isSystem).count == 4)
    }

    @Test func migrationMapsEachExistingWalletKindToBuiltInCategory() throws {
        let key = "aaaabbbbccccddddeeeeffffgggghhhhiiiijjjjkkkkllllmmmmnnnnoooopppp"
        let location = TestSupport.makeLocation()
        let keychain = TestKeychainStore(items: ["database-key": Data(key.utf8)])

        let partialMigrator = DatabaseManager.makeMigrator(upTo: "v3_bank_sync")
        let fixtureManager = try DatabaseManager(locationProvider: location, keychain: keychain, migrator: partialMigrator)
        let fixtureRepo = CashRunwayRepository(databaseManager: fixtureManager)
        try fixtureRepo.seedIfNeeded()

        let cashWallet = WalletBuilder().with(name: "Cash Wallet").with(kind: .cash).build()
        let cardWallet = WalletBuilder().with(name: "Card Wallet").with(kind: .card).build()
        let accountWallet = WalletBuilder().with(name: "Account Wallet").with(kind: .account).build()
        let otherWallet = WalletBuilder().with(name: "Other Wallet").with(kind: .other).build()
        try fixtureRepo.saveWallet(cashWallet)
        try fixtureRepo.saveWallet(cardWallet)
        try fixtureRepo.saveWallet(accountWallet)
        try fixtureRepo.saveWallet(otherWallet)

        let fullManager = try DatabaseManager(locationProvider: location, keychain: keychain)
        let repo = CashRunwayRepository(databaseManager: fullManager)
        try repo.seedIfNeeded()

        let categories = try repo.walletCategories()
        let wallets = try repo.wallets()

        let categoryByID = Dictionary(uniqueKeysWithValues: categories.map { ($0.id, $0) })
        let walletByName = Dictionary(uniqueKeysWithValues: wallets.map { ($0.name, $0) })

        #expect(walletByName["Cash Wallet"]?.categoryID == WalletCategory.builtIn(byKind: .cash).id)
        #expect(walletByName["Card Wallet"]?.categoryID == WalletCategory.builtIn(byKind: .card).id)
        #expect(walletByName["Account Wallet"]?.categoryID == WalletCategory.builtIn(byKind: .account).id)
        #expect(walletByName["Other Wallet"]?.categoryID == WalletCategory.builtIn(byKind: .other).id)

        #expect(categoryByID[WalletCategory.builtIn(byKind: .cash).id]?.isSystem == true)
        #expect(categoryByID[WalletCategory.builtIn(byKind: .card).id]?.isSystem == true)
        #expect(categoryByID[WalletCategory.builtIn(byKind: .account).id]?.isSystem == true)
        #expect(categoryByID[WalletCategory.builtIn(byKind: .other).id]?.isSystem == true)
    }

    @Test func migrationPreservesExistingWalletData() throws {
        let key = "aaaabbbbccccddddeeeeffffgggghhhhiiiijjjjkkkkllllmmmmnnnnoooopppp"
        let location = TestSupport.makeLocation()
        let keychain = TestKeychainStore(items: ["database-key": Data(key.utf8)])

        let partialMigrator = DatabaseManager.makeMigrator(upTo: "v3_bank_sync")
        let fixtureManager = try DatabaseManager(locationProvider: location, keychain: keychain, migrator: partialMigrator)
        let fixtureRepo = CashRunwayRepository(databaseManager: fixtureManager)
        try fixtureRepo.seedIfNeeded()

        let wallet = WalletBuilder()
            .with(name: "Savings")
            .with(kind: .account)
            .with(startingBalanceMinor: 500_000)
            .with(currentBalanceMinor: 750_000)
            .with(sortOrder: 7)
            .build()
        try fixtureRepo.saveWallet(wallet)

        let fullManager = try DatabaseManager(locationProvider: location, keychain: keychain)
        let repo = CashRunwayRepository(databaseManager: fullManager)
        try repo.seedIfNeeded()

        let migrated = try #require(try repo.wallets().first { $0.id == wallet.id })
        #expect(migrated.name == "Savings")
        #expect(migrated.kind == .account)
        #expect(migrated.categoryID == WalletCategory.builtIn(byKind: .account).id)
        #expect(migrated.startingBalanceMinor == 500_000)
        #expect(migrated.currentBalanceMinor == 750_000)
        #expect(migrated.sortOrder == 7)
    }

    @Test func createAndPersistCustomWalletCategory() throws {
        let repository = try TestSupport.makeRepository()
        try repository.seedIfNeeded()

        let category = WalletCategory(
            id: UUID(),
            name: "Crypto",
            kind: .other,
            isSystem: false,
            createdAt: .now,
            updatedAt: .now
        )
        try repository.saveWalletCategory(category)

        let categories = try repository.walletCategories()
        #expect(categories.contains { $0.id == category.id && $0.name == "Crypto" })
    }

    @Test func rejectsEmptyCategoryName() throws {
        let repository = try TestSupport.makeRepository()
        try repository.seedIfNeeded()

        let category = WalletCategory(
            id: UUID(),
            name: "",
            kind: .other,
            isSystem: false,
            createdAt: .now,
            updatedAt: .now
        )

        #expect(throws: CashRunwayError.validation(L10n.string("Category name cannot be empty."))) {
            try repository.saveWalletCategory(category)
        }
    }

    @Test func rejectsWhitespaceOnlyCategoryName() throws {
        let repository = try TestSupport.makeRepository()
        try repository.seedIfNeeded()

        let category = WalletCategory(
            id: UUID(),
            name: "   ",
            kind: .other,
            isSystem: false,
            createdAt: .now,
            updatedAt: .now
        )

        #expect(throws: CashRunwayError.validation(L10n.string("Category name cannot be empty."))) {
            try repository.saveWalletCategory(category)
        }
    }

    @Test func rejectsCaseInsensitiveDuplicateName() throws {
        let repository = try TestSupport.makeRepository()
        try repository.seedIfNeeded()

        let first = WalletCategory(
            id: UUID(),
            name: "Vacation Fund",
            kind: .other,
            isSystem: false,
            createdAt: .now,
            updatedAt: .now
        )
        try repository.saveWalletCategory(first)

        let duplicate = WalletCategory(
            id: UUID(),
            name: "  vacation FUND  ",
            kind: .other,
            isSystem: false,
            createdAt: .now,
            updatedAt: .now
        )
        #expect(throws: CashRunwayError.validation(L10n.string("A category with this name already exists."))) {
            try repository.saveWalletCategory(duplicate)
        }
    }

    @Test func rejectsDuplicateBuiltInDisplayName() throws {
        let repository = try TestSupport.makeRepository()
        try repository.seedIfNeeded()

        let duplicate = WalletCategory(
            id: UUID(),
            name: L10n.walletKind(.cash),
            kind: .other,
            isSystem: false,
            createdAt: .now,
            updatedAt: .now
        )
        #expect(throws: CashRunwayError.validation(L10n.string("A category with this name already exists."))) {
            try repository.saveWalletCategory(duplicate)
        }
    }

    @Test func assignsCustomCategoryToNewWallet() throws {
        let repository = try TestSupport.makeRepository()
        try repository.seedIfNeeded()

        let category = WalletCategory(
            id: UUID(),
            name: "Investment",
            kind: .other,
            isSystem: false,
            createdAt: .now,
            updatedAt: .now
        )
        try repository.saveWalletCategory(category)

        let wallet = WalletBuilder()
            .with(name: "Brokerage")
            .with(kind: .other)
            .with(categoryID: category.id)
            .build()
        try repository.saveWallet(wallet)

        let saved = try #require(try repository.wallets().first { $0.id == wallet.id })
        #expect(saved.categoryID == category.id)
        #expect(saved.kind == .other)
    }

    @Test func changingWalletCategoryDoesNotAlterFinancialValues() throws {
        let repository = try TestSupport.makeRepository()
        try repository.seedIfNeeded()
        try TestSupport.seedFixtureWallets(into: repository)

        let category = WalletCategory(
            id: UUID(),
            name: "Business",
            kind: .other,
            isSystem: false,
            createdAt: .now,
            updatedAt: .now
        )
        try repository.saveWalletCategory(category)

        var wallet = try #require(try repository.wallets().first)
        let originalBalance = wallet.currentBalanceMinor
        let originalStartingBalance = wallet.startingBalanceMinor
        let originalID = wallet.id

        wallet.categoryID = category.id
        wallet.kind = .other
        try repository.saveWallet(wallet)

        let updated = try #require(try repository.wallets().first { $0.id == originalID })
        #expect(updated.categoryID == category.id)
        #expect(updated.currentBalanceMinor == originalBalance)
        #expect(updated.startingBalanceMinor == originalStartingBalance)
    }

    @Test func customCategoryIsReusableByMultipleWallets() throws {
        let repository = try TestSupport.makeRepository()
        try repository.seedIfNeeded()

        let category = WalletCategory(
            id: UUID(),
            name: "Emergency Fund",
            kind: .other,
            isSystem: false,
            createdAt: .now,
            updatedAt: .now
        )
        try repository.saveWalletCategory(category)

        let walletA = WalletBuilder().with(name: "A").with(kind: .other).with(categoryID: category.id).build()
        let walletB = WalletBuilder().with(name: "B").with(kind: .other).with(categoryID: category.id).build()
        try repository.saveWallet(walletA)
        try repository.saveWallet(walletB)

        let wallets = try repository.wallets()
        #expect(wallets.filter { $0.categoryID == category.id }.count == 2)
    }

    @Test func newBackupRoundTripsCustomCategoriesAndAssignments() throws {
        let repository = try TestSupport.makeRepository()
        try repository.seedIfNeeded()

        let category = WalletCategory(
            id: UUID(),
            name: "Crypto",
            kind: .other,
            isSystem: false,
            createdAt: .now,
            updatedAt: .now
        )
        try repository.saveWalletCategory(category)

        let wallet = WalletBuilder()
            .with(name: "Ledger")
            .with(kind: .other)
            .with(categoryID: category.id)
            .with(startingBalanceMinor: 1_000_000)
            .with(currentBalanceMinor: 1_000_000)
            .build()
        try repository.saveWallet(wallet)

        let backup = try repository.exportFullBackup()
        #expect(backup.metadata.version == 2)
        #expect(backup.walletCategories.contains { $0.id == category.id })
        #expect(backup.wallets.contains { $0.categoryID == category.id })

        let target = try TestSupport.makeRepository()
        try target.restoreFullBackup(backup)

        let restoredWallet = try #require(try target.wallets().first { $0.id == wallet.id })
        #expect(restoredWallet.categoryID == category.id)
        #expect(try target.walletCategories().contains { $0.id == category.id && $0.name == "Crypto" })
    }

    @Test func olderVersion1BackupRemainsImportable() throws {
        let repository = try TestSupport.makeRepository()
        try repository.seedIfNeeded()
        let wallet = WalletBuilder().with(name: "Legacy").with(kind: .card).build()
        try repository.saveWallet(wallet)

        let backup = try repository.exportFullBackup()
        var version1Backup = backup
        version1Backup.metadata.version = 1
        version1Backup.walletCategories = []
        version1Backup.wallets = backup.wallets.map {
            BackupWallet(
                id: $0.id,
                name: $0.name,
                kind: $0.kind,
                categoryID: nil,
                colorHex: $0.colorHex,
                iconName: $0.iconName,
                startingBalanceMinor: $0.startingBalanceMinor,
                currentBalanceMinor: $0.currentBalanceMinor,
                isArchived: $0.isArchived,
                sortOrder: $0.sortOrder,
                createdAt: $0.createdAt,
                updatedAt: $0.updatedAt
            )
        }

        let target = try TestSupport.makeRepository()
        try target.restoreFullBackup(version1Backup)

        let restored = try #require(try target.wallets().first { $0.id == wallet.id })
        #expect(restored.kind == .card)
        #expect(restored.categoryID == WalletCategory.builtIn(byKind: .card).id)
    }

    @Test func backupValidationRejectsDanglingWalletCategoryReference() throws {
        let repository = try TestSupport.makeRepository()
        try repository.seedIfNeeded()
        let wallet = WalletBuilder().with(name: "Dangling").with(kind: .cash).build()
        try repository.saveWallet(wallet)

        var backup = try repository.exportFullBackup()
        backup.wallets[0].categoryID = UUID()

        do {
            try BackupValidator.validate(backup)
            Issue.record("Expected backup validation to throw brokenReference error.")
        } catch let error as BackupError {
            if case .brokenReference = error {
                // expected
            } else {
                Issue.record("Expected brokenReference error, got \(error).")
            }
        }
    }
}
