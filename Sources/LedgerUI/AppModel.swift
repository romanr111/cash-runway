import Foundation
import Observation
import SwiftUI
#if canImport(LedgerCore)
import LedgerCore
#endif

public typealias LedgerCategory = Category
public typealias LedgerLabel = Label

@MainActor
@Observable
public final class LedgerAppModel {
    public var repository: LedgerRepository
    public var csvService: CSVService
    public var lockStore: AppLockStore

    public var wallets: [Wallet] = []
    public var expenseCategories: [LedgerCategory] = []
    public var incomeCategories: [LedgerCategory] = []
    public var labels: [LedgerLabel] = []
    public var transactions: [TransactionListItem] = []
    public var budgets: [BudgetProgress] = []
    public var templates: [RecurringTemplate] = []
    public var instances: [RecurringInstance] = []
    public var dashboardSnapshot: DashboardSnapshot?
    public var timelineSnapshot: TimelineSnapshot?
    public var overviewSnapshot: OverviewSnapshot?

    public var selectedMonthKey = DateKeys.monthKey(for: .now)
    public var selectedWalletID: UUID?
    public var transactionQuery = TransactionQuery()
    public var isLocked = false
    public var lockMessage: String?
    public var errorMessage: String?
    public var successMessage: String?

    public init(
        repository: LedgerRepository = LedgerRepository(),
        lockStore: AppLockStore = AppLockStore(keychain: KeychainStore(service: "dev.roman.spendee-ledger"))
    ) {
        self.repository = repository
        self.csvService = CSVService(repository: repository)
        self.lockStore = lockStore
    }

    public func bootstrap() {
        do {
            try repository.seedIfNeeded()
            try repository.runMaintenance()
            try repository.refreshRecurringInstances()
            try reloadAll()
            if let configuration = lockStore.configuration(), configuration.isEnabled {
                isLocked = true
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    public func reloadAll() throws {
        wallets = try repository.wallets()
        expenseCategories = try repository.categories(kind: .expense)
        incomeCategories = try repository.categories(kind: .income)
        labels = try repository.labels()
        templates = try repository.recurringTemplates()
        instances = try repository.recurringInstances()
        budgets = try repository.budgets(monthKey: selectedMonthKey)
        transactionQuery.walletID = selectedWalletID
        transactions = try repository.transactions(query: transactionQuery)
        dashboardSnapshot = try repository.dashboard(monthKey: selectedMonthKey, walletID: selectedWalletID)
        timelineSnapshot = try repository.timelineSnapshot(monthKey: selectedMonthKey, walletID: selectedWalletID, query: transactionQuery)
        overviewSnapshot = try repository.overviewSnapshot(monthKey: selectedMonthKey, walletID: selectedWalletID)
    }

    public func unlock(pin: String) {
        guard lockStore.validate(pin: pin) else {
            lockMessage = "Incorrect PIN."
            return
        }
        isLocked = false
        lockMessage = nil
    }

    public func unlockWithBiometrics() async {
        guard await lockStore.unlockWithBiometrics() else {
            lockMessage = "Biometric unlock failed."
            return
        }
        isLocked = false
        lockMessage = nil
    }

    public func enableLock(pin: String, biometrics: Bool) {
        do {
            try lockStore.save(pin: pin, biometrics: biometrics, backgroundLockSeconds: 15)
            successMessage = "App lock updated."
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    public func saveTransaction(_ draft: TransactionDraft) {
        saveTransaction(draft, recurringTemplate: nil)
    }

    public func saveTransaction(_ draft: TransactionDraft, recurringTemplate: RecurringTemplate?) {
        runMutation(success: "Transaction saved.") {
            try repository.saveTransaction(draft)
            if let recurringTemplate {
                try repository.saveRecurringTemplate(recurringTemplate)
            }
        }
    }

    public func deleteTransaction(id: UUID) {
        runMutation(success: "Transaction deleted.") {
            try repository.deleteTransaction(id: id)
        }
    }

    public func saveWallet(_ wallet: Wallet) {
        runMutation(success: "Wallet saved.") {
            try repository.saveWallet(wallet)
        }
    }

    public func saveCategory(_ category: LedgerCategory) {
        runMutation(success: "Category saved.") {
            try repository.saveCategory(category)
        }
    }

    public func saveLabel(_ label: LedgerLabel) {
        runMutation(success: "Label saved.") {
            try repository.saveLabel(label)
        }
    }

    public func saveBudget(_ budget: Budget) {
        runMutation(success: "Budget saved.") {
            try repository.saveBudget(budget)
        }
    }

    public func archiveBudget(_ budget: Budget) {
        var archived = budget
        archived.isArchived = true
        archived.updatedAt = .now
        saveBudget(archived)
    }

    public func saveTemplate(_ template: RecurringTemplate) {
        runMutation(success: "Recurring template saved.") {
            try repository.saveRecurringTemplate(template)
        }
    }

    public func saveInstance(_ instance: RecurringInstance) {
        runMutation(success: "Occurrence updated.") {
            try repository.saveRecurringInstance(instance)
            try repository.refreshRecurringInstances()
        }
    }

    public func postInstance(_ instance: RecurringInstance) {
        runMutation(success: "Occurrence posted.") {
            try repository.postRecurringInstance(id: instance.id)
        }
    }

    public func skipInstance(_ instance: RecurringInstance) {
        runMutation(success: "Occurrence skipped.") {
            try repository.skipRecurringInstance(id: instance.id)
        }
    }

    public func mergeCategory(oldCategoryID: UUID, into newCategoryID: UUID) {
        runMutation(success: "Categories merged.") {
            try repository.mergeCategory(oldCategoryID: oldCategoryID, into: newCategoryID)
        }
    }

    public func categoryManagementItems(kind: CategoryKind) -> [CategoryManagementItem] {
        (try? repository.categoryManagementItems(kind: kind)) ?? []
    }

    public func toggleCategoryVisibility(_ category: LedgerCategory) {
        var updated = category
        updated.isArchived.toggle()
        updated.updatedAt = .now
        saveCategory(updated)
    }

    public func reorderCategories(kind: CategoryKind, orderedCategoryIDs: [UUID]) {
        runMutation(success: "Categories reordered.") {
            try repository.reorderCategories(kind: kind, orderedCategoryIDs: orderedCategoryIDs)
        }
    }

    public func importCSV(data: Data, fileName: String, mapping: CSVImportMapping) {
        do {
            let result = try csvService.importCSV(data: data, fileName: fileName, mapping: mapping)
            try reloadAll()
            if result.rowErrors.isEmpty {
                successMessage = "CSV imported. Added \(result.insertedTransactions) transactions."
            } else {
                let details = result.rowErrors.prefix(3)
                    .map { "row \($0.rowNumber): \($0.message)" }
                    .joined(separator: "; ")
                successMessage = "CSV imported. Added \(result.insertedTransactions) transactions, skipped \(result.job.invalidRows). \(details)"
            }
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    public func exportCSV() -> String {
        (try? csvService.exportCSV(query: transactionQuery)) ?? ""
    }

    public func previewCSV(data: Data) throws -> CSVImportPreview {
        try csvService.preview(data: data)
    }

    public func detectPreset(headers: [String]) -> CSVPreset {
        csvService.detectPreset(headers: headers)
    }

    public func handleForegroundResume() {
        do {
            try repository.runMaintenance()
            try repository.refreshRecurringInstances()
            try reloadAll()
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func runMutation(success message: String, _ mutation: () throws -> Void) {
        do {
            try mutation()
            try reloadAll()
            successMessage = message
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
