import Foundation
import Testing
@testable import CashRunwayCore

@Suite
struct ModelSerializationTests {
    @Test func walletCodableRoundTrip() throws {
        let original = Wallet(
            id: UUID(),
            name: "Main",
            kind: .card,
            colorHex: "#60788A",
            iconName: "wallet.pass.fill",
            startingBalanceMinor: 5_000_000,
            currentBalanceMinor: 4_999_999,
            isArchived: false,
            sortOrder: 0,
            createdAt: Date(timeIntervalSince1970: 1_700_000_000),
            updatedAt: Date(timeIntervalSince1970: 1_700_000_100)
        )
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(Wallet.self, from: data)
        #expect(decoded == original)
    }

    @Test func categoryCodableRoundTrip() throws {
        let original = Category(
            id: UUID(),
            name: "Groceries",
            kind: .expense,
            iconName: "cart",
            colorHex: "#1CC389",
            parentID: nil,
            isSystem: false,
            isArchived: false,
            sortOrder: 3,
            createdAt: .now,
            updatedAt: .now
        )
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(Category.self, from: data)
        #expect(decoded == original)
    }

    @Test func labelCodableRoundTrip() throws {
        let now = Date()
        let original = Label(
            id: UUID(),
            name: "Travel",
            colorHex: "#EBAA3A",
            createdAt: now,
            updatedAt: now
        )
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(Label.self, from: data)
        #expect(decoded == original)
    }

    @Test func transactionCodableRoundTrip() throws {
        let now = Date()
        let original = CashRunwayTransaction(
            id: UUID(),
            walletID: UUID(),
            type: .expense,
            linkedTransferID: nil,
            amountMinor: -12_350,
            occurredAt: Date(timeIntervalSince1970: 1_700_000_000),
            localDayKey: 20231215,
            localMonthKey: 202312,
            categoryID: UUID(),
            merchant: "Test Merchant",
            note: "Test note",
            isDeleted: false,
            source: .manual,
            recurringTemplateID: nil,
            recurringInstanceID: nil,
            createdAt: now,
            updatedAt: now
        )
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(CashRunwayTransaction.self, from: data)
        #expect(decoded == original)
    }

    @Test func recurringTemplateCodableRoundTrip() throws {
        let now = Date()
        let original = RecurringTemplate(
            id: UUID(),
            kind: .income,
            walletID: UUID(),
            counterpartyWalletID: nil,
            amountMinor: 100_000,
            categoryID: UUID(),
            merchant: "Salary",
            note: "Monthly",
            ruleType: .monthly,
            ruleInterval: 1,
            dayOfMonth: 15,
            weekday: nil,
            startDate: Date(timeIntervalSince1970: 1_600_000_000),
            endDate: Date(timeIntervalSince1970: 1_800_000_000),
            isActive: true,
            createdAt: now,
            updatedAt: now
        )
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(RecurringTemplate.self, from: data)
        #expect(decoded == original)
    }

    @Test func recurringInstanceCodableRoundTrip() throws {
        let now = Date()
        let original = RecurringInstance(
            id: UUID(),
            templateID: UUID(),
            dueDate: Date(timeIntervalSince1970: 1_700_000_000),
            dayKey: 20231215,
            status: .scheduled,
            linkedTransactionID: nil,
            overrideAmountMinor: nil,
            overrideCategoryID: nil,
            overrideNote: nil,
            overrideMerchant: nil,
            createdAt: now,
            updatedAt: now
        )
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(RecurringInstance.self, from: data)
        #expect(decoded == original)
    }

    @Test func importJobCodableRoundTrip() throws {
        let now = Date()
        let original = ImportJob(
            id: UUID(),
            sourceName: "csv",
            fileName: "test.csv",
            status: .committed,
            totalRows: 102,
            validRows: 100,
            invalidRows: 2,
            duplicateRows: 0,
            startedAt: now,
            finishedAt: now,
            errorSummary: nil
        )
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(ImportJob.self, from: data)
        #expect(decoded == original)
    }

    @Test func budgetCodableRoundTrip() throws {
        let now = Date()
        let original = Budget(
            id: UUID(),
            categoryID: UUID(),
            monthKey: 202405,
            limitMinor: 50_000,
            isArchived: false,
            createdAt: now,
            updatedAt: now
        )
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(Budget.self, from: data)
        #expect(decoded == original)
    }

    @Test func walletHashableConsistency() throws {
        let original = Wallet(
            id: UUID(),
            name: "Main",
            kind: .card,
            colorHex: "#60788A",
            iconName: "wallet.pass.fill",
            startingBalanceMinor: 5_000_000,
            currentBalanceMinor: 4_999_999,
            isArchived: false,
            sortOrder: 0,
            createdAt: Date(timeIntervalSince1970: 1_700_000_000),
            updatedAt: Date(timeIntervalSince1970: 1_700_000_100)
        )
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(Wallet.self, from: data)
        var hasher1 = Hasher()
        original.hash(into: &hasher1)
        var hasher2 = Hasher()
        decoded.hash(into: &hasher2)
        #expect(hasher1.finalize() == hasher2.finalize())
    }

    @Test func transactionQueryEquatable() {
        var a = TransactionQuery()
        var b = TransactionQuery()
        #expect(a == b)

        a.searchText = "foo"
        #expect(a != b)

        b.searchText = "foo"
        #expect(a == b)

        a.walletID = UUID()
        #expect(a != b)
    }

    @Test func enumRawValueStability() {
        #expect(WalletKind.cash.rawValue == "cash")
        #expect(CategoryKind.expense.rawValue == "expense")
        #expect(TransactionKind.transferOut.rawValue == "transfer_out")
        #expect(TransactionSource.bankSync.rawValue == "bank_sync")
        #expect(TransactionSource.importCSV.rawValue == "import_csv")
        #expect(RecurringTemplateKind.transfer.rawValue == "transfer")
        #expect(RecurrenceRuleType.monthly.rawValue == "monthly")
        #expect(RecurringInstanceStatus.scheduled.rawValue == "scheduled")
        #expect(ImportJobStatus.committed.rawValue == "committed")
    }
}
