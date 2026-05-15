import Foundation
import Testing
@testable import CashRunwayCore

@Suite(.serialized)
struct RepositoryCRUDTests {
    @Test func saveWalletInsertsAndUpdates() throws {
        let repository = try TestSupport.makeRepository()
        try repository.seedIfNeeded()

        let wallet = Wallet(
            id: UUID(),
            name: "Test Wallet",
            kind: .cash,
            colorHex: "#FF0000",
            iconName: "dollarsign.circle",
            startingBalanceMinor: 100_000,
            currentBalanceMinor: 100_000,
            isArchived: false,
            sortOrder: 99,
            createdAt: .now,
            updatedAt: .now
        )
        try repository.saveWallet(wallet)

        var wallets = try repository.wallets()
        let inserted = try #require(wallets.first { $0.id == wallet.id })
        #expect(inserted.name == "Test Wallet")
        #expect(inserted.kind == .cash)
        #expect(inserted.sortOrder == 99)

        var updated = inserted
        updated.name = "Updated Wallet"
        updated.currentBalanceMinor = 200_000
        try repository.saveWallet(updated)

        wallets = try repository.wallets()
        let fetched = try #require(wallets.first { $0.id == wallet.id })
        #expect(fetched.name == "Updated Wallet")
        #expect(fetched.currentBalanceMinor == 200_000)
    }

    @Test func saveCategoryInsertsAndUpdates() throws {
        let repository = try TestSupport.makeRepository()
        try repository.seedIfNeeded()

        let category = Category(
            id: UUID(),
            name: "Test Category",
            kind: .expense,
            iconName: "star",
            colorHex: "#00FF00",
            parentID: nil,
            isSystem: false,
            isArchived: false,
            sortOrder: 999,
            createdAt: .now,
            updatedAt: .now
        )
        try repository.saveCategory(category)

        var categories = try repository.categories(kind: .expense)
        let inserted = try #require(categories.first { $0.id == category.id })
        #expect(inserted.name == "Test Category")
        #expect(inserted.iconName == "star")

        var updated = inserted
        updated.name = "Updated Category"
        updated.colorHex = "#FF00FF"
        try repository.saveCategory(updated)

        categories = try repository.categories(kind: .expense)
        let fetched = try #require(categories.first { $0.id == category.id })
        #expect(fetched.name == "Updated Category")
        #expect(fetched.colorHex == "#FF00FF")
    }

    @Test func saveLabelInsertsAndUpdates() throws {
        let repository = try TestSupport.makeRepository()
        try repository.seedIfNeeded()

        let label = Label(
            id: UUID(),
            name: "Test Label",
            colorHex: "#0000FF",
            createdAt: .now,
            updatedAt: .now
        )
        try repository.saveLabel(label)

        var labels = try repository.labels()
        let inserted = try #require(labels.first { $0.id == label.id })
        #expect(inserted.name == "Test Label")

        var updated = inserted
        updated.name = "Updated Label"
        try repository.saveLabel(updated)

        labels = try repository.labels()
        let fetched = try #require(labels.first { $0.id == label.id })
        #expect(fetched.name == "Updated Label")
    }

    @Test func saveRecurringTemplateUpdatesExisting() throws {
        let repository = try TestSupport.makeRepository()
        try repository.seedIfNeeded()
        let wallets = try repository.wallets()
        let wallet = try #require(wallets.first)
        let category = try #require(try repository.categories(kind: .expense).first)

        let template = RecurringTemplate(
            id: UUID(),
            kind: .expense,
            walletID: wallet.id,
            counterpartyWalletID: nil,
            amountMinor: 10_000,
            categoryID: category.id,
            merchant: "Internet",
            note: "Monthly",
            ruleType: .monthly,
            ruleInterval: 1,
            dayOfMonth: 1,
            weekday: nil,
            startDate: .now,
            endDate: nil,
            isActive: true,
            createdAt: .now,
            updatedAt: .now
        )
        try repository.saveRecurringTemplate(template)

        var templates = try repository.recurringTemplates()
        let inserted = try #require(templates.first { $0.id == template.id })
        #expect(inserted.amountMinor == 10_000)

        var updated = inserted
        updated.amountMinor = 20_000
        updated.note = "Updated"
        try repository.saveRecurringTemplate(updated)

        templates = try repository.recurringTemplates()
        let fetched = try #require(templates.first { $0.id == template.id })
        #expect(fetched.amountMinor == 20_000)
        #expect(fetched.note == "Updated")
    }

    @Test func saveRecurringInstanceUpdatesExisting() throws {
        let repository = try TestSupport.makeRepository()
        try repository.seedIfNeeded()
        let wallets = try repository.wallets()
        let wallet = try #require(wallets.first)
        let category = try #require(try repository.categories(kind: .expense).first)

        let template = RecurringTemplate(
            id: UUID(),
            kind: .expense,
            walletID: wallet.id,
            counterpartyWalletID: nil,
            amountMinor: 10_000,
            categoryID: category.id,
            merchant: "Internet",
            note: "Monthly",
            ruleType: .monthly,
            ruleInterval: 1,
            dayOfMonth: 1,
            weekday: nil,
            startDate: .now,
            endDate: nil,
            isActive: true,
            createdAt: .now,
            updatedAt: .now
        )
        try repository.saveRecurringTemplate(template)
        try repository.refreshRecurringInstances()

        var instances = try repository.recurringInstances()
        let instance = try #require(instances.first { $0.templateID == template.id })
        #expect(instance.status == .scheduled)

        var updated = instance
        updated.status = .skipped
        updated.overrideNote = "Skipped this month"
        try repository.saveRecurringInstance(updated)

        instances = try repository.recurringInstances()
        let fetched = try #require(instances.first { $0.id == instance.id })
        #expect(fetched.status == .skipped)
        #expect(fetched.overrideNote == "Skipped this month")
    }
}
