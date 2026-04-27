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
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    public func saveTransaction(_ draft: TransactionDraft) {
        saveTransaction(draft, recurringTemplate: nil)
    }

    public func saveTransaction(_ draft: TransactionDraft, recurringTemplate: RecurringTemplate?) {
        runMutation {
            try repository.saveTransaction(draft)
            if let recurringTemplate {
                try repository.saveRecurringTemplate(recurringTemplate)
            }
        }
    }

    public func deleteTransaction(id: UUID) {
        runMutation {
            try repository.deleteTransaction(id: id)
        }
    }

    public func saveWallet(_ wallet: Wallet) {
        runMutation {
            try repository.saveWallet(wallet)
        }
    }

    public func saveCategory(_ category: LedgerCategory) {
        runMutation {
            try repository.saveCategory(category)
        }
    }

    public func saveLabel(_ label: LedgerLabel) {
        runMutation {
            try repository.saveLabel(label)
        }
    }

    public func saveBudget(_ budget: Budget) {
        runMutation {
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
        runMutation {
            try repository.saveRecurringTemplate(template)
        }
    }

    public func saveInstance(_ instance: RecurringInstance) {
        runMutation {
            try repository.saveRecurringInstance(instance)
            try repository.refreshRecurringInstances()
        }
    }

    public func postInstance(_ instance: RecurringInstance) {
        runMutation {
            try repository.postRecurringInstance(id: instance.id)
        }
    }

    public func skipInstance(_ instance: RecurringInstance) {
        runMutation {
            try repository.skipRecurringInstance(id: instance.id)
        }
    }

    public func mergeCategory(oldCategoryID: UUID, into newCategoryID: UUID) {
        runMutation {
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
        runMutation {
            try repository.reorderCategories(kind: kind, orderedCategoryIDs: orderedCategoryIDs)
        }
    }

    public func importCSV(data: Data, fileName: String, mapping: CSVImportMapping) {
        do {
            _ = try csvService.importCSV(data: data, fileName: fileName, mapping: mapping)
            try reloadAll()
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

    private func runMutation(_ mutation: () throws -> Void) {
        do {
            try mutation()
            try reloadAll()
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
