import Foundation
@testable import CashRunwayCore

// MARK: - TransactionBuilder

struct TransactionBuilder {
    private var kind: TransactionDraft.Kind = .expense
    private var walletID: UUID?
    private var destinationWalletID: UUID?
    private var amountMinor: Int64 = 1_000
    private var occurredAt: Date = Date(timeIntervalSince1970: 1_800_000_000)
    private var categoryID: UUID?
    private var labelIDs: [UUID] = []
    private var merchant: String = "Test Merchant"
    private var note: String = "Test note"
    private var source: TransactionSource = .manual
    private var recurringTemplateID: UUID?
    private var recurringInstanceID: UUID?
    private var importJobID: UUID?
    private var importFingerprint: String?

    func with(kind: TransactionDraft.Kind) -> Self {
        var copy = self; copy.kind = kind; return copy
    }

    func with(walletID: UUID) -> Self {
        var copy = self; copy.walletID = walletID; return copy
    }

    func with(destinationWalletID: UUID?) -> Self {
        var copy = self; copy.destinationWalletID = destinationWalletID; return copy
    }

    func with(amountMinor: Int64) -> Self {
        var copy = self; copy.amountMinor = amountMinor; return copy
    }

    func with(occurredAt: Date) -> Self {
        var copy = self; copy.occurredAt = occurredAt; return copy
    }

    func with(categoryID: UUID?) -> Self {
        var copy = self; copy.categoryID = categoryID; return copy
    }

    func with(labelIDs: [UUID]) -> Self {
        var copy = self; copy.labelIDs = labelIDs; return copy
    }

    func with(merchant: String) -> Self {
        var copy = self; copy.merchant = merchant; return copy
    }

    func with(note: String) -> Self {
        var copy = self; copy.note = note; return copy
    }

    func with(source: TransactionSource) -> Self {
        var copy = self; copy.source = source; return copy
    }

    func with(recurringTemplateID: UUID?) -> Self {
        var copy = self; copy.recurringTemplateID = recurringTemplateID; return copy
    }

    func with(importJobID: UUID?) -> Self {
        var copy = self; copy.importJobID = importJobID; return copy
    }

    func with(importFingerprint: String?) -> Self {
        var copy = self; copy.importFingerprint = importFingerprint; return copy
    }

    func build() -> TransactionDraft {
        TransactionDraft(
            kind: kind,
            walletID: walletID ?? UUID(),
            destinationWalletID: destinationWalletID,
            amountMinor: amountMinor,
            occurredAt: occurredAt,
            categoryID: categoryID,
            labelIDs: labelIDs,
            merchant: merchant,
            note: note,
            source: source,
            recurringTemplateID: recurringTemplateID,
            recurringInstanceID: recurringInstanceID,
            importJobID: importJobID,
            importFingerprint: importFingerprint
        )
    }
}

// MARK: - WalletBuilder

struct WalletBuilder {
    private var id: UUID = UUID()
    private var name: String = "Test Wallet"
    private var kind: WalletKind = .card
    private var colorHex: String? = "#60788A"
    private var iconName: String? = "wallet.pass.fill"
    private var startingBalanceMinor: Int64 = 0
    private var currentBalanceMinor: Int64 = 0
    private var isArchived: Bool = false
    private var sortOrder: Int = 0
    private var createdAt: Date = .now
    private var updatedAt: Date = .now

    func with(id: UUID) -> Self {
        var copy = self; copy.id = id; return copy
    }

    func with(name: String) -> Self {
        var copy = self; copy.name = name; return copy
    }

    func with(kind: WalletKind) -> Self {
        var copy = self; copy.kind = kind; return copy
    }

    func with(startingBalanceMinor: Int64) -> Self {
        var copy = self; copy.startingBalanceMinor = startingBalanceMinor; return copy
    }

    func with(currentBalanceMinor: Int64) -> Self {
        var copy = self; copy.currentBalanceMinor = currentBalanceMinor; return copy
    }

    func with(colorHex: String?) -> Self {
        var copy = self; copy.colorHex = colorHex; return copy
    }

    func with(iconName: String?) -> Self {
        var copy = self; copy.iconName = iconName; return copy
    }

    func with(isArchived: Bool) -> Self {
        var copy = self; copy.isArchived = isArchived; return copy
    }

    func with(sortOrder: Int) -> Self {
        var copy = self; copy.sortOrder = sortOrder; return copy
    }

    func build() -> Wallet {
        Wallet(
            id: id,
            name: name,
            kind: kind,
            colorHex: colorHex,
            iconName: iconName,
            startingBalanceMinor: startingBalanceMinor,
            currentBalanceMinor: currentBalanceMinor,
            isArchived: isArchived,
            sortOrder: sortOrder,
            createdAt: createdAt,
            updatedAt: updatedAt
        )
    }
}

// MARK: - CategoryBuilder

struct CategoryBuilder {
    private var id: UUID = UUID()
    private var name: String = "Test Category"
    private var kind: CategoryKind = .expense
    private var iconName: String? = "tag.fill"
    private var colorHex: String? = "#FF5733"
    private var parentID: UUID?
    private var isSystem: Bool = false
    private var isArchived: Bool = false
    private var sortOrder: Int = 0
    private var createdAt: Date = .now
    private var updatedAt: Date = .now

    func with(id: UUID) -> Self {
        var copy = self; copy.id = id; return copy
    }

    func with(name: String) -> Self {
        var copy = self; copy.name = name; return copy
    }

    func with(kind: CategoryKind) -> Self {
        var copy = self; copy.kind = kind; return copy
    }

    func with(iconName: String?) -> Self {
        var copy = self; copy.iconName = iconName; return copy
    }

    func with(colorHex: String?) -> Self {
        var copy = self; copy.colorHex = colorHex; return copy
    }

    func with(parentID: UUID?) -> Self {
        var copy = self; copy.parentID = parentID; return copy
    }

    func with(isSystem: Bool) -> Self {
        var copy = self; copy.isSystem = isSystem; return copy
    }

    func with(isArchived: Bool) -> Self {
        var copy = self; copy.isArchived = isArchived; return copy
    }

    func with(sortOrder: Int) -> Self {
        var copy = self; copy.sortOrder = sortOrder; return copy
    }

    // Explicit module prefix avoids ambiguity with ObjectiveC.Category from objc/runtime.h.
    func build() -> CashRunwayCore.Category {
        CashRunwayCore.Category(
            id: id,
            name: name,
            kind: kind,
            iconName: iconName,
            colorHex: colorHex,
            parentID: parentID,
            isSystem: isSystem,
            isArchived: isArchived,
            sortOrder: sortOrder,
            createdAt: createdAt,
            updatedAt: updatedAt
        )
    }
}

// MARK: - LabelBuilder

struct LabelBuilder {
    private var id: UUID = UUID()
    private var name: String = "Test Label"
    private var colorHex: String? = "#1CC389"
    private var createdAt: Date = .now
    private var updatedAt: Date = .now

    func with(id: UUID) -> Self {
        var copy = self; copy.id = id; return copy
    }

    func with(name: String) -> Self {
        var copy = self; copy.name = name; return copy
    }

    func with(colorHex: String?) -> Self {
        var copy = self; copy.colorHex = colorHex; return copy
    }

    func build() -> Label {
        Label(id: id, name: name, colorHex: colorHex, createdAt: createdAt, updatedAt: updatedAt)
    }
}

// MARK: - CSVImportMappingBuilder

struct CSVImportMappingBuilder {
    private var dateColumn: String = "Date"
    private var amountColumn: String? = "Amount"
    private var debitColumn: String?
    private var creditColumn: String?
    private var merchantColumn: String? = "Merchant"
    private var noteColumn: String? = "Note"
    private var categoryColumn: String? = "Category name"
    private var labelsColumn: String? = "Labels"
    private var walletID: UUID?
    private var defaultKind: TransactionDraft.Kind = .expense
    private var typeColumn: String?
    private var walletColumn: String?
    private var currencyColumn: String?
    private var authorColumn: String?

    func with(dateColumn: String) -> Self {
        var copy = self; copy.dateColumn = dateColumn; return copy
    }

    func with(amountColumn: String?) -> Self {
        var copy = self; copy.amountColumn = amountColumn; return copy
    }

    func with(merchantColumn: String?) -> Self {
        var copy = self; copy.merchantColumn = merchantColumn; return copy
    }

    func with(noteColumn: String?) -> Self {
        var copy = self; copy.noteColumn = noteColumn; return copy
    }

    func with(categoryColumn: String?) -> Self {
        var copy = self; copy.categoryColumn = categoryColumn; return copy
    }

    func with(labelsColumn: String?) -> Self {
        var copy = self; copy.labelsColumn = labelsColumn; return copy
    }

    func with(walletID: UUID?) -> Self {
        var copy = self; copy.walletID = walletID; return copy
    }

    func with(defaultKind: TransactionDraft.Kind) -> Self {
        var copy = self; copy.defaultKind = defaultKind; return copy
    }

    func with(typeColumn: String?) -> Self {
        var copy = self; copy.typeColumn = typeColumn; return copy
    }

    func with(walletColumn: String?) -> Self {
        var copy = self; copy.walletColumn = walletColumn; return copy
    }

    func with(currencyColumn: String?) -> Self {
        var copy = self; copy.currencyColumn = currencyColumn; return copy
    }

    func with(authorColumn: String?) -> Self {
        var copy = self; copy.authorColumn = authorColumn; return copy
    }

    func build() -> CSVImportMapping {
        CSVImportMapping(
            dateColumn: dateColumn,
            amountColumn: amountColumn,
            debitColumn: debitColumn,
            creditColumn: creditColumn,
            merchantColumn: merchantColumn,
            noteColumn: noteColumn,
            categoryColumn: categoryColumn,
            labelsColumn: labelsColumn,
            walletID: walletID,
            defaultKind: defaultKind,
            typeColumn: typeColumn,
            walletColumn: walletColumn,
            currencyColumn: currencyColumn,
            authorColumn: authorColumn
        )
    }
}
