import BackgroundTasks
import Darwin
import Foundation
import SwiftUI

@main
struct CashRunwayApp: App {
    @Environment(\.scenePhase) private var scenePhase
    private let maintenanceCoordinator = BackgroundMaintenanceCoordinator()

    init() {
        #if DEBUG
        DebugCSVImportSelfTest.runIfRequested()
        #endif
        maintenanceCoordinator.register()
        maintenanceCoordinator.schedule()
    }

    var body: some Scene {
        WindowGroup {
            CashRunwayRootView()
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .background || phase == .active {
                maintenanceCoordinator.schedule()
            }
        }
    }
}

private final class BackgroundMaintenanceCoordinator {
    private let identifier = "dev.roman.cash-runway.maintenance"
    private var hasRegistered = false

    func register() {
        guard !hasRegistered else { return }
        hasRegistered = BGTaskScheduler.shared.register(forTaskWithIdentifier: identifier, using: nil) { task in
            guard let task = task as? BGProcessingTask else {
                task.setTaskCompleted(success: false)
                return
            }
            self.handle(task: task)
        }
    }

    func schedule() {
        let request = BGProcessingTaskRequest(identifier: identifier)
        request.requiresNetworkConnectivity = false
        request.requiresExternalPower = false
        request.earliestBeginDate = Date(timeIntervalSinceNow: 15 * 60)
        do {
            try BGTaskScheduler.shared.submit(request)
        } catch {
        }
    }

    private func handle(task: BGProcessingTask) {
        schedule()
        let taskBox = BackgroundProcessingTaskBox(task)
        let maintenanceTask = Task.detached(priority: .background) {
            do {
                let repository = CashRunwayRepository()
                try repository.runMaintenance()
                try repository.refreshRecurringInstances()
                return true
            } catch {
                return false
            }
        }

        task.expirationHandler = {
            maintenanceTask.cancel()
        }

        Task {
            let success = await maintenanceTask.value
            taskBox.task.setTaskCompleted(success: success)
        }
    }
}

private final class BackgroundProcessingTaskBox: @unchecked Sendable {
    let task: BGProcessingTask

    init(_ task: BGProcessingTask) {
        self.task = task
    }
}

#if DEBUG
private enum DebugCSVImportSelfTest {
    static func runIfRequested() {
        let environment = ProcessInfo.processInfo.environment
        guard let csvPath = environment["CASH_RUNWAY_IMPORT_SELF_TEST_CSV"] else { return }

        let resultPath = environment["CASH_RUNWAY_IMPORT_SELF_TEST_RESULT"]
        do {
            let summary = try run(csvPath: csvPath)
            try write("PASS \(summary)", to: resultPath)
            Darwin.exit(0)
        } catch {
            try? write("FAIL \(error.localizedDescription)", to: resultPath)
            Darwin.exit(1)
        }
    }

    private static func run(csvPath: String) throws -> String {
        let csvURL = URL(fileURLWithPath: csvPath)
        let fileManager = FileManager.default
        let workingDirectory = fileManager.temporaryDirectory.appendingPathComponent("CashRunwayImportSelfTest-\(UUID().uuidString)", isDirectory: true)
        try fileManager.createDirectory(at: workingDirectory, withIntermediateDirectories: true)
        defer { try? fileManager.removeItem(at: workingDirectory) }

        let databaseURL = workingDirectory.appendingPathComponent("cash-runway.sqlite")
        let databaseManager = try DatabaseManager(
            locationProvider: DatabaseLocationProvider(
                appGroupIdentifier: nil,
                databaseURLOverride: databaseURL,
                directoryName: "ImportSelfTest"
            ),
            allowsDestructiveRecovery: true
        )
        let repository = CashRunwayRepository(databaseManager: databaseManager)
        try repository.seedIfNeeded()

        let service = CSVService(repository: repository)
        let data = try CSVImportFileReader.readData(from: csvURL)
        let preview = try service.preview(data: data)
        guard service.detectPreset(headers: preview.headers) == .cashRunwayWallet else {
            throw CashRunwayError.validation("Self-test CSV headers were not detected as Cash Runway wallet CSV.")
        }

        guard let walletID = try repository.wallets().first?.id else {
            throw CashRunwayError.validation("Self-test repository has no wallet.")
        }
        let result = try service.importCSV(
            data: data,
            fileName: csvURL.lastPathComponent,
            mapping: CSVImportMapping(
                dateColumn: "Date",
                amountColumn: "Amount",
                debitColumn: nil,
                creditColumn: nil,
                merchantColumn: nil,
                noteColumn: "Note",
                categoryColumn: "Category name",
                labelsColumn: "Labels",
                walletID: walletID,
                defaultKind: .expense,
                typeColumn: "Type",
                walletColumn: "Wallet",
                currencyColumn: "Currency",
                authorColumn: "Author"
            )
        )
        let importedCount = try repository.transactions(query: .init(), limit: nil).filter { $0.source == .importCSV }.count
        guard result.insertedTransactions == importedCount, importedCount > 0 else {
            throw CashRunwayError.validation("Self-test import inserted \(result.insertedTransactions) rows but found \(importedCount).")
        }
        return "inserted=\(importedCount) file=\(csvURL.lastPathComponent)"
    }

    private static func write(_ output: String, to resultPath: String?) throws {
        guard let resultPath, !resultPath.isEmpty else { return }
        let resultURL = URL(fileURLWithPath: resultPath)
        try FileManager.default.createDirectory(at: resultURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(output.utf8).write(to: resultURL, options: .atomic)
    }
}
#endif
