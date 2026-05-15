import Foundation
import GRDB
import Testing
@testable import CashRunwayCore

@Suite(.serialized)
struct CashRunwayPerformanceTests {
    @Test func benchmarkScenariosMatchPlanCounts() {
        #expect(BenchmarkScenario.allCases.map(\.transactionCount) == [1_000, 10_000, 50_000, 150_000])
    }

    @Test func fixtureGeneratorPopulatesRequestedCount() throws {
        let repository = try makeRepository()
        let generator = FixtureGenerator(repository: repository)
        try generator.populate(scenario: .small)

        let transactionCount = try repository.databaseManager.dbQueue.read { db in
            try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM transactions WHERE type != 'transfer_in'") ?? 0
        }
        #expect(transactionCount == 1_000)
    }

    @Test func fixtureGeneratorSeedsLabelsAndRecurringSamples() throws {
        let repository = try makeRepository()
        let generator = FixtureGenerator(repository: repository)
        try generator.populate(scenario: .small)

        #expect(try repository.labels().count >= 4)
        #expect(try repository.recurringTemplates().count >= 3)
        #expect(try repository.recurringInstances().isEmpty == false)
    }

    @Test func dashboardLoadTimingGate() throws {
        let repository = try makeRepository()
        let generator = FixtureGenerator(repository: repository)
        try generator.populate(scenario: .medium)
        let monthKey = DateKeys.monthKey(for: .now)
        let clock = ContinuousClock()

        let elapsed = clock.measure {
            _ = try? repository.dashboard(monthKey: monthKey)
        }
        #expect(seconds(elapsed) < 2)
    }

    @Test func transactionQueryTimingGate() throws {
        let repository = try makeRepository()
        let generator = FixtureGenerator(repository: repository)
        try generator.populate(scenario: .medium)
        let clock = ContinuousClock()

        let elapsed = clock.measure {
            _ = try? repository.transactions(query: .init())
        }
        #expect(seconds(elapsed) < 2)
    }

    @Test func searchTimingGate() throws {
        let repository = try makeRepository()
        let generator = FixtureGenerator(repository: repository)
        try generator.populate(seed: BenchmarkScenario.medium.seed, transactionCount: BenchmarkScenario.medium.transactionCount)
        let clock = ContinuousClock()

        let elapsed = clock.measure {
            _ = try? repository.transactions(query: .init(searchText: "Synthetic"))
        }
        #expect(seconds(elapsed) < 2)
    }

    @Test func importBatchAndAggregateRebuildTimingGate() throws {
        let repository = try makeRepository()
        try repository.seedIfNeeded()
        try TestSupport.seedFixtureWallets(into: repository)
        let walletID = try #require(try repository.wallets().first?.id)
        let walletName = try #require(try repository.wallets().first?.name)
        let service = CSVService(repository: repository)
        var lines = ["Date,Wallet,Type,Category name,Amount,Currency,Note,Labels,Author"]
        for index in 0..<BenchmarkScenario.small.transactionCount {
            let type = index % 10 == 0 ? "Income" : "Expense"
            let category = type == "Income" ? "Salary" : "Groceries"
            let amount = type == "Income" ? "1000.00" : "-12.34"
            let note = "txn-\(index)"
            lines.append("2026-04-\(String(format: "%02d", (index % 28) + 1))T10:00:00Z,\(walletName),\(type),\(category),\(amount),UAH,\(note),,")
        }
        let data = Data(lines.joined(separator: "\n").utf8)
        let clock = ContinuousClock()

        var importOutcome: Result<CSVImportResult, any Error>?
        let elapsed = clock.measure {
            importOutcome = Result {
                try service.importCSV(
                    data: data,
                    fileName: "synthetic-wallet.csv",
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
            }
        }

        let result = try #require(importOutcome).get()
        #expect(result.insertedTransactions == BenchmarkScenario.small.transactionCount)
        #expect(seconds(elapsed) < 5)
    }

    @Test func overviewSnapshotTimingGate() throws {
        let repository = try makeRepository()
        let generator = FixtureGenerator(repository: repository)
        try generator.populate(scenario: .medium)
        let monthKey = DateKeys.monthKey(for: .now)
        let clock = ContinuousClock()

        let elapsed = clock.measure {
            _ = try? repository.overviewSnapshot(monthKey: monthKey)
        }
        #expect(seconds(elapsed) < 2)
    }

    @Test func timelineSnapshotTimingGate() throws {
        let repository = try makeRepository()
        let generator = FixtureGenerator(repository: repository)
        try generator.populate(scenario: .medium)
        let monthKey = DateKeys.monthKey(for: .now)
        let clock = ContinuousClock()

        let elapsed = clock.measure {
            _ = try? repository.timelineSnapshot(monthKey: monthKey)
        }
        #expect(seconds(elapsed) < 2)
    }

    @Test func allBarsTimingGate() throws {
        let repository = try makeRepository()
        let generator = FixtureGenerator(repository: repository)
        try generator.populate(scenario: .medium)
        let clock = ContinuousClock()

        let elapsed = clock.measure {
            _ = try? repository.allBars()
        }
        #expect(seconds(elapsed) < 2)
    }

    @Test func runMaintenanceTimingGate() throws {
        let repository = try makeRepository()
        let generator = FixtureGenerator(repository: repository)
        try generator.populate(scenario: .medium)
        let clock = ContinuousClock()

        let elapsed = clock.measure {
            _ = try? repository.runMaintenance()
        }
        #expect(seconds(elapsed) < 5)
    }

    @Test func fixturePopulationTimingGate() throws {
        let repository = try makeRepository()
        let generator = FixtureGenerator(repository: repository)
        let clock = ContinuousClock()

        let elapsed = clock.measure {
            try? generator.populate(scenario: .medium)
        }
        // .medium = 10K transactions inserted one-by-one; known bottleneck.
        // Gate is generous to avoid CI flakiness while flagging regressions.
        #expect(seconds(elapsed) < 30)
    }

    private func makeRepository() throws -> CashRunwayRepository {
        let baseURL = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("cash-runway-perf-tests", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let location = DatabaseLocationProvider(
            appGroupIdentifier: nil,
            databaseURLOverride: baseURL.appendingPathComponent("cash-runway.sqlite"),
            directoryName: UUID().uuidString
        )
        return CashRunwayRepository(databaseManager: try DatabaseManager(locationProvider: location, keychain: TestKeychainStore()))
    }

    private func seconds(_ duration: Duration) -> Double {
        let components = duration.components
        return Double(components.seconds) + Double(components.attoseconds) / 1_000_000_000_000_000_000
    }
}
