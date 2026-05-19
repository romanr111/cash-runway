import BackgroundTasks
import Darwin
import Foundation
import GRDB
import SwiftUI
import UIKit

@main
struct CashRunwayApp: App {
    @Environment(\.scenePhase) private var scenePhase
    private let maintenanceCoordinator = BackgroundMaintenanceCoordinator()
    private let runtime: CashRunwayAppRuntime

    init() {
        #if DEBUG
        DebugDataRecoveryAttempt.runIfRequested()
        DebugCSVImportSelfTest.runIfRequested()
        #endif
        if ProcessInfo.processInfo.environment["CASH_RUNWAY_UI_TEST_MODE"] == "1" {
            UIView.setAnimationsEnabled(false)
        }
        runtime = CashRunwayAppRuntime.bootstrap()
        maintenanceCoordinator.register()
        maintenanceCoordinator.schedule()
    }

    var body: some Scene {
        WindowGroup {
            CashRunwayRootView(
                model: runtime.model,
                startupError: runtime.startupError,
                onboardingStore: runtime.onboardingStore,
                bypassOnboarding: runtime.bypassOnboarding
            )
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
                let repository = try CashRunwayRepository()
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
private enum DebugDataRecoveryAttempt {
    struct ProbeResult {
        var transactionCount: Int
        var walletCount: Int
    }

    static func runIfRequested() {
        let environment = ProcessInfo.processInfo.environment
        guard environment["CASH_RUNWAY_RECOVERY_ATTEMPT"] == "1" else { return }

        do {
            let report = try run()
            try write(report)
            print(report)
            Darwin.exit(0)
        } catch {
            let report = "FAIL recovery_attempt error=\(error.localizedDescription)"
            try? write(report)
            print(report)
            Darwin.exit(1)
        }
    }

    private static func run() throws -> String {
        let fileManager = FileManager.default
        let databaseURL = try DatabaseLocationProvider().databaseURL()
        let directoryURL = databaseURL.deletingLastPathComponent()
        let recoveryDirectory = directoryURL.appendingPathComponent("Recovery", isDirectory: true)

        guard fileManager.fileExists(atPath: recoveryDirectory.path) else {
            return "NOOP recovery_attempt reason=no_recovery_directory"
        }

        let backups = try fileManager
            .contentsOfDirectory(at: recoveryDirectory, includingPropertiesForKeys: [.fileSizeKey])
            .filter { url in
                let name = url.lastPathComponent
                return name.hasPrefix("cash-runway.sqlite.")
                    && name.hasSuffix(".bak")
                    && !name.contains("-wal")
                    && !name.contains("-shm")
            }
            .map { url -> (url: URL, size: Int) in
                let values = try url.resourceValues(forKeys: [.fileSizeKey])
                return (url, values.fileSize ?? 0)
            }
            .sorted { lhs, rhs in
                if lhs.size == rhs.size {
                    return lhs.url.lastPathComponent < rhs.url.lastPathComponent
                }
                return lhs.size > rhs.size
            }

        guard let backup = backups.first else {
            return "NOOP recovery_attempt reason=no_database_backup"
        }
        let backupName = backup.url.lastPathComponent

        let keychain = KeychainStore(service: "dev.roman.cash-runway")
        guard let keyData = try keychain.read(account: "database-key"),
              let key = String(data: keyData, encoding: .utf8),
              !key.isEmpty
        else {
            return
                "NOOP recovery_attempt reason=no_readable_database_key " +
                "backup=\(backupName) backup_bytes=\(backup.size)"
        }

        let activeProbe = try? probe(databaseURL, key: key)
        guard let backupProbe = try? probe(backup.url, key: key) else {
            return
                "NOOP recovery_attempt reason=backup_not_decryptable_with_current_key " +
                "backup=\(backupName) backup_bytes=\(backup.size) " +
                "active_transactions=\(activeProbe?.transactionCount ?? -1)"
        }

        let activeTransactions = activeProbe?.transactionCount ?? -1
        guard backupProbe.transactionCount > activeTransactions else {
            return
                "NOOP recovery_attempt reason=backup_not_better " +
                "backup=\(backupName) backup_transactions=\(backupProbe.transactionCount) " +
                "active_transactions=\(activeTransactions)"
        }

        let stamp = ISO8601DateFormatter().string(from: Date()).replacingOccurrences(of: ":", with: "-")
        let attemptDirectory = recoveryDirectory.appendingPathComponent("RestoreAttempt-\(stamp)", isDirectory: true)
        try fileManager.createDirectory(at: attemptDirectory, withIntermediateDirectories: true)

        for suffix in ["", "-wal", "-shm"] {
            let activeURL = URL(fileURLWithPath: databaseURL.path + suffix)
            guard fileManager.fileExists(atPath: activeURL.path) else { continue }
            try fileManager.copyItem(
                at: activeURL,
                to: attemptDirectory.appendingPathComponent(activeURL.lastPathComponent)
            )
            try fileManager.removeItem(at: activeURL)
        }

        let backupBaseName = backup.url.lastPathComponent.dropLast(".bak".count)
        for (sourceSuffix, destinationSuffix) in [("", ""), ("-wal", "-wal"), ("-shm", "-shm")] {
            let backupComponent = "\(backupBaseName)\(sourceSuffix).bak"
            let backupURL = recoveryDirectory.appendingPathComponent(backupComponent)
            guard fileManager.fileExists(atPath: backupURL.path) else { continue }
            let destinationURL = URL(fileURLWithPath: databaseURL.path + destinationSuffix)
            try fileManager.copyItem(at: backupURL, to: destinationURL)
        }

        let restoredProbe = try probe(databaseURL, key: key)
        return
            "RESTORED recovery_attempt " +
            "backup=\(backupName) backup_bytes=\(backup.size) " +
            "restored_transactions=\(restoredProbe.transactionCount) " +
            "restored_wallets=\(restoredProbe.walletCount) " +
            "previous_active_transactions=\(activeTransactions)"
    }

    private static func probe(_ url: URL, key: String) throws -> ProbeResult {
        var configuration = Configuration()
        configuration.prepareDatabase { database in
            try database.usePassphrase(key)
        }

        let queue = try DatabaseQueue(path: url.path, configuration: configuration)
        return try queue.read { database in
            ProbeResult(
                transactionCount: try Int.fetchOne(database, sql: "SELECT COUNT(*) FROM transactions") ?? 0,
                walletCount: try Int.fetchOne(database, sql: "SELECT COUNT(*) FROM wallets") ?? 0
            )
        }
    }

    private static func write(_ report: String) throws {
        let documents = try FileManager.default.url(
            for: .documentDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        try report.write(
            to: documents.appendingPathComponent("recovery-attempt-report.txt"),
            atomically: true,
            encoding: .utf8
        )
    }
}

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
        let workingDirectoryName = "CashRunwayImportSelfTest-\(UUID().uuidString)"
        let workingDirectory = fileManager.temporaryDirectory.appendingPathComponent(
            workingDirectoryName,
            isDirectory: true
        )
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
        let importedCount = try repository.transactions(query: .init(), limit: nil)
            .filter { $0.source == .importCSV }
            .count
        guard result.insertedTransactions == importedCount, importedCount > 0 else {
            throw CashRunwayError.validation(
                "Self-test import inserted \(result.insertedTransactions) rows " +
                "but found \(importedCount)."
            )
        }
        return "inserted=\(importedCount) file=\(csvURL.lastPathComponent)"
    }

    private static func write(_ output: String, to resultPath: String?) throws {
        guard let resultPath, !resultPath.isEmpty else { return }
        let resultURL = URL(fileURLWithPath: resultPath)
        try FileManager.default.createDirectory(
            at: resultURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try Data(output.utf8).write(to: resultURL, options: .atomic)
    }
}
#endif
