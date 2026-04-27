import BackgroundTasks
import SwiftUI

@main
struct SpendeeLedgerApp: App {
    @Environment(\.scenePhase) private var scenePhase
    private let maintenanceCoordinator = BackgroundMaintenanceCoordinator()

    init() {
        maintenanceCoordinator.register()
        maintenanceCoordinator.schedule()
    }

    var body: some Scene {
        WindowGroup {
            LedgerRootView()
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .background || phase == .active {
                maintenanceCoordinator.schedule()
            }
        }
    }
}

private final class BackgroundMaintenanceCoordinator {
    private let identifier = "dev.roman.spendee-ledger.maintenance"
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
                let repository = LedgerRepository()
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
