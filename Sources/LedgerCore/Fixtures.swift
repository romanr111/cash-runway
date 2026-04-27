import Foundation

public enum BenchmarkScenario: Int, CaseIterable, Sendable {
    case small = 1_000
    case medium = 10_000
    case large = 50_000
    case scale = 150_000

    public var transactionCount: Int { rawValue }

    public var seed: UInt64 {
        switch self {
        case .small: 42
        case .medium: 84
        case .large: 168
        case .scale: 336
        }
    }
}

public struct FixtureGenerator {
    public struct SeededRNG: RandomNumberGenerator {
        private var state: UInt64

        public init(seed: UInt64) {
            self.state = seed
        }

        public mutating func next() -> UInt64 {
            state = 6364136223846793005 &* state &+ 1
            return state
        }
    }

    public let repository: LedgerRepository

    public init(repository: LedgerRepository) {
        self.repository = repository
    }

    public func populate(scenario: BenchmarkScenario) throws {
        try populate(seed: scenario.seed, transactionCount: scenario.transactionCount)
    }

    public func populate(seed: UInt64 = 42, transactionCount: Int) throws {
        try repository.seedIfNeeded()
        try seedFixtureLabelsIfNeeded()
        try seedRecurringTemplatesIfNeeded()
        var rng = SeededRNG(seed: seed)
        let wallets = try repository.wallets()
        let expenseCategories = try repository.categories(kind: .expense)
        let incomeCategories = try repository.categories(kind: .income)
        let labels = try repository.labels()
        let calendar = DateKeys.calendar

        for index in 0..<transactionCount {
            let isIncome = Int.random(in: 0..<10, using: &rng) == 0
            let wallet = wallets[Int.random(in: 0..<wallets.count, using: &rng)]
            let date = calendar.date(byAdding: .day, value: -Int.random(in: 0..<3650, using: &rng), to: .now) ?? .now
            let amount = Int64(Int.random(in: 300...40_000, using: &rng))
            let category = isIncome
                ? incomeCategories[Int.random(in: 0..<incomeCategories.count, using: &rng)]
                : expenseCategories[Int.random(in: 0..<expenseCategories.count, using: &rng)]
            let labelIDs = pickLabelIDs(from: labels, rng: &rng)
            try repository.saveTransaction(
                TransactionDraft(
                    kind: isIncome ? .income : .expense,
                    walletID: wallet.id,
                    amountMinor: amount,
                    occurredAt: date,
                    categoryID: category.id,
                    labelIDs: labelIDs,
                    merchant: category.name,
                    note: "Synthetic transaction \(index)",
                    source: .manual
                )
            )
        }
        try repository.refreshRecurringInstances()
    }

    private func seedFixtureLabelsIfNeeded() throws {
        guard try repository.labels().isEmpty else { return }
        let now = Date()
        for (index, name) in ["Home", "Family", "Travel", "Subscriptions"].enumerated() {
            try repository.saveLabel(
                Label(
                    id: UUID(uuidString: String(format: "44444444-4444-4444-4444-%012d", index + 1)) ?? UUID(),
                    name: name,
                    colorHex: ["#60788A", "#1CC389", "#EBAA3A", "#7E57C2"][index],
                    createdAt: now,
                    updatedAt: now
                )
            )
        }
    }

    private func seedRecurringTemplatesIfNeeded() throws {
        guard try repository.recurringTemplates().isEmpty else { return }
        let wallets = try repository.wallets()
        guard let primaryWallet = wallets.first else { return }
        let savingsWallet = wallets.dropFirst().first
        let expenseCategory = try repository.categories(kind: .expense).first
        let incomeCategory = try repository.categories(kind: .income).first
        let now = Date()

        if let expenseCategory {
            try repository.saveRecurringTemplate(
                RecurringTemplate(
                    id: UUID(uuidString: "55555555-5555-5555-5555-555555555551") ?? UUID(),
                    kind: .expense,
                    walletID: primaryWallet.id,
                    counterpartyWalletID: nil,
                    amountMinor: 12_000,
                    categoryID: expenseCategory.id,
                    merchant: "Internet",
                    note: "Monthly recurring fixture",
                    ruleType: .monthly,
                    ruleInterval: 1,
                    dayOfMonth: Calendar.current.component(.day, from: now),
                    weekday: nil,
                    startDate: now,
                    endDate: nil,
                    isActive: true,
                    createdAt: now,
                    updatedAt: now
                )
            )
        }

        if let incomeCategory {
            try repository.saveRecurringTemplate(
                RecurringTemplate(
                    id: UUID(uuidString: "55555555-5555-5555-5555-555555555552") ?? UUID(),
                    kind: .income,
                    walletID: primaryWallet.id,
                    counterpartyWalletID: nil,
                    amountMinor: 180_000,
                    categoryID: incomeCategory.id,
                    merchant: "Salary",
                    note: "Monthly salary fixture",
                    ruleType: .monthly,
                    ruleInterval: 1,
                    dayOfMonth: Calendar.current.component(.day, from: now),
                    weekday: nil,
                    startDate: now,
                    endDate: nil,
                    isActive: true,
                    createdAt: now,
                    updatedAt: now
                )
            )
        }

        if let savingsWallet {
            try repository.saveRecurringTemplate(
                RecurringTemplate(
                    id: UUID(uuidString: "55555555-5555-5555-5555-555555555553") ?? UUID(),
                    kind: .transfer,
                    walletID: primaryWallet.id,
                    counterpartyWalletID: savingsWallet.id,
                    amountMinor: 35_000,
                    categoryID: nil,
                    merchant: "Savings Transfer",
                    note: "Monthly transfer fixture",
                    ruleType: .monthly,
                    ruleInterval: 1,
                    dayOfMonth: Calendar.current.component(.day, from: now),
                    weekday: nil,
                    startDate: now,
                    endDate: nil,
                    isActive: true,
                    createdAt: now,
                    updatedAt: now
                )
            )
        }
    }

    private func pickLabelIDs(from labels: [Label], rng: inout SeededRNG) -> [UUID] {
        guard !labels.isEmpty else { return [] }
        let decision = Int.random(in: 0..<5, using: &rng)
        switch decision {
        case 0:
            return [labels[Int.random(in: 0..<labels.count, using: &rng)].id]
        case 1 where labels.count > 1:
            let first = Int.random(in: 0..<labels.count, using: &rng)
            var second = Int.random(in: 0..<labels.count, using: &rng)
            while second == first {
                second = Int.random(in: 0..<labels.count, using: &rng)
            }
            return [labels[first].id, labels[second].id]
        default:
            return []
        }
    }
}
