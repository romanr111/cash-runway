import Foundation
import GRDB
import Testing
@testable import LedgerCore

struct LedgerPerformanceTests {
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

    @Test func dashboardTimingScaffold() throws {
        let repository = try makeRepository()
        let generator = FixtureGenerator(repository: repository)
        try generator.populate(scenario: .medium)
        let monthKey = DateKeys.monthKey(for: .now)
        let clock = ContinuousClock()

        let elapsed = clock.measure {
            _ = try? repository.dashboard(monthKey: monthKey)
        }
        #expect(elapsed.components.seconds >= 0)
    }

    @Test func searchTimingScaffold() throws {
        let repository = try makeRepository()
        let generator = FixtureGenerator(repository: repository)
        try generator.populate(seed: BenchmarkScenario.medium.seed, transactionCount: BenchmarkScenario.medium.transactionCount)
        let clock = ContinuousClock()

        let elapsed = clock.measure {
            _ = try? repository.transactions(query: .init(searchText: "Synthetic"))
        }
        #expect(elapsed.components.seconds >= 0)
    }

    private func makeRepository() throws -> LedgerRepository {
        let baseURL = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("spendee-ledger-perf-tests", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let location = DatabaseLocationProvider(
            appGroupIdentifier: nil,
            databaseURLOverride: baseURL.appendingPathComponent("ledger.sqlite"),
            directoryName: UUID().uuidString
        )
        return LedgerRepository(databaseManager: try DatabaseManager(locationProvider: location))
    }
}
