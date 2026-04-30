import Foundation
import GRDB

private struct AggregateContribution {
    let walletID: UUID
    let monthKey: Int
    let dayKey: Int
    let type: TransactionKind
    let amountMinor: Int64
    let categoryID: UUID?
}

public final class CashRunwayRepository: @unchecked Sendable {
    public let databaseManager: DatabaseManager

    public init(databaseManager: DatabaseManager = try! DatabaseManager(allowsDestructiveRecovery: true)) {
        self.databaseManager = databaseManager
    }

    public func seedIfNeeded() throws {
        try databaseManager.dbQueue.write { db in
            let count = try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM wallets") ?? 0
            if count == 0 {
                let now = Date()
                try db.execute(
                    sql: """
                    INSERT INTO wallets (id, name, kind, color_hex, icon_name, starting_balance_minor, current_balance_minor, is_archived, sort_order, created_at, updated_at)
                    VALUES (?, ?, ?, ?, ?, ?, ?, 0, 0, ?, ?)
                    """,
                    arguments: [
                        UUID(uuidString: "33333333-3333-3333-3333-333333333331")!.uuidString,
                        "Main Wallet",
                        WalletKind.card.rawValue,
                        "#60788A",
                        "wallet.pass.fill",
                        5_000_000,
                        5_000_000,
                        now,
                        now,
                    ]
                )
                try db.execute(
                    sql: """
                    INSERT INTO wallets (id, name, kind, color_hex, icon_name, starting_balance_minor, current_balance_minor, is_archived, sort_order, created_at, updated_at)
                    VALUES (?, ?, ?, ?, ?, ?, ?, 0, 1, ?, ?)
                    """,
                    arguments: [
                        UUID(uuidString: "33333333-3333-3333-3333-333333333332")!.uuidString,
                        "Savings",
                        WalletKind.account.rawValue,
                        "#1CC389",
                        "banknote.fill",
                        360_000,
                        360_000,
                        now,
                        now,
                    ]
                )
            }

            let categoryCount = try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM categories") ?? 0
            if categoryCount == 0 {
                let now = Date()
                for (index, category) in SeedCategories.all.enumerated() {
                    try db.execute(
                        sql: """
                        INSERT INTO categories (id, name, kind, icon_name, color_hex, parent_id, is_system, is_archived, sort_order, created_at, updated_at)
                        VALUES (?, ?, ?, ?, ?, NULL, 1, 0, ?, ?, ?)
                        """,
                        arguments: [
                            category.id.uuidString,
                            category.name,
                            category.kind.rawValue,
                            category.iconName,
                            category.colorHex,
                            index,
                            now,
                            now,
                        ]
                    )
                }
            }

            let budgetCount = try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM budgets") ?? 0
            if budgetCount == 0, let housing = SeedCategories.all.first(where: { $0.name == "Housing" }) {
                let now = Date()
                let monthKey = DateKeys.monthKey(for: .now)
                try db.execute(
                    sql: """
                    INSERT INTO budgets (id, category_id, month_key, limit_minor, is_archived, created_at, updated_at)
                    VALUES (?, ?, ?, ?, 0, ?, ?)
                    """,
                    arguments: [UUID().uuidString, housing.id.uuidString, monthKey, 90_000, now, now]
                )
                try recomputeBudgetSnapshots(db, monthKeys: [monthKey])
            }
        }
    }

    public func wallets() throws -> [Wallet] {
        try databaseManager.dbQueue.read { db in
            try Row.fetchAll(db, sql: "SELECT * FROM wallets WHERE is_archived = 0 ORDER BY sort_order, name").map(Self.wallet)
        }
    }

    public func categories(kind: CategoryKind? = nil) throws -> [Category] {
        try databaseManager.dbQueue.read { db in
            if let kind {
                return try Row.fetchAll(
                    db,
                    sql: "SELECT * FROM categories WHERE is_archived = 0 AND kind = ? ORDER BY sort_order, name",
                    arguments: [kind.rawValue]
                ).map(Self.category)
            }
            return try Row.fetchAll(db, sql: "SELECT * FROM categories WHERE is_archived = 0 ORDER BY kind, sort_order, name").map(Self.category)
        }
    }

    public func labels() throws -> [Label] {
        try databaseManager.dbQueue.read { db in
            try Row.fetchAll(db, sql: "SELECT * FROM labels ORDER BY name").map(Self.label)
        }
    }

    public func budgets(monthKey: Int) throws -> [BudgetProgress] {
        try databaseManager.dbQueue.read { db in
            try Row.fetchAll(
                db,
                sql: """
                SELECT b.*, c.name AS category_name, c.kind AS category_kind, c.icon_name AS category_icon_name, c.color_hex AS category_color_hex,
                       c.parent_id AS category_parent_id, c.is_system AS category_is_system, c.is_archived AS category_is_archived,
                       c.sort_order AS category_sort_order, c.created_at AS category_created_at, c.updated_at AS category_updated_at,
                       COALESCE(s.spent_minor, 0) AS spent_minor,
                       COALESCE(s.remaining_minor, b.limit_minor) AS remaining_minor,
                       COALESCE(s.percent_used_bp, 0) AS percent_used_bp
                FROM budgets b
                JOIN categories c ON c.id = b.category_id
                LEFT JOIN budget_progress_snapshot s ON s.budget_id = b.id AND s.month_key = b.month_key
                WHERE b.month_key = ? AND b.is_archived = 0
                ORDER BY c.name
                """,
                arguments: [monthKey]
            ).map { row in
                BudgetProgress(
                    id: UUID(uuidString: row["id"])!,
                    budget: try Self.budget(row),
                    category: try Self.category(prefixed: "category_", row: row),
                    spentMinor: row["spent_minor"],
                    remainingMinor: row["remaining_minor"],
                    percentUsedBP: row["percent_used_bp"]
                )
            }
        }
    }

    public func recurringTemplates() throws -> [RecurringTemplate] {
        try databaseManager.dbQueue.read { db in
            try Row.fetchAll(db, sql: "SELECT * FROM recurring_templates ORDER BY created_at DESC").map(Self.recurringTemplate)
        }
    }

    public func recurringInstances() throws -> [RecurringInstance] {
        try databaseManager.dbQueue.read { db in
            try Row.fetchAll(db, sql: "SELECT * FROM recurring_instances ORDER BY due_date").map(Self.recurringInstance)
        }
    }

    public func saveWallet(_ wallet: Wallet) throws {
        try databaseManager.dbQueue.write { db in
            try db.execute(
                sql: """
                INSERT INTO wallets (id, name, kind, color_hex, icon_name, starting_balance_minor, current_balance_minor, is_archived, sort_order, created_at, updated_at)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                ON CONFLICT(id) DO UPDATE SET
                    name = excluded.name,
                    kind = excluded.kind,
                    color_hex = excluded.color_hex,
                    icon_name = excluded.icon_name,
                    starting_balance_minor = excluded.starting_balance_minor,
                    current_balance_minor = excluded.current_balance_minor,
                    is_archived = excluded.is_archived,
                    sort_order = excluded.sort_order,
                    updated_at = excluded.updated_at
                """,
                arguments: [
                    wallet.id.uuidString, wallet.name, wallet.kind.rawValue, wallet.colorHex, wallet.iconName,
                    wallet.startingBalanceMinor, wallet.currentBalanceMinor, wallet.isArchived, wallet.sortOrder,
                    wallet.createdAt, wallet.updatedAt,
                ]
            )
        }
    }

    public func deleteWallet(id: UUID) throws {
        let activeCount = try databaseManager.dbQueue.read { db in
            try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM wallets WHERE is_archived = 0") ?? 0
        }
        guard activeCount > 1 else {
            throw CashRunwayError.validation("At least one active wallet must remain.")
        }

        let txIDs = try databaseManager.dbQueue.read { db in
            let rows = try Row.fetchAll(
                db,
                sql: "SELECT id, linked_transfer_id FROM transactions WHERE wallet_id = ?",
                arguments: [id.uuidString]
            )
            var ids = Set<UUID>()
            for row in rows {
                if let txID = UUID(uuidString: row["id"]) {
                    ids.insert(txID)
                }
                if let linkedID = (row["linked_transfer_id"] as String?).flatMap(UUID.init) {
                    ids.insert(linkedID)
                }
            }
            return Array(ids)
        }

        for txID in txIDs {
            do {
                try deleteTransaction(id: txID)
            } catch CashRunwayError.notFound {
                // Already deleted as a linked transfer; safe to ignore.
            }
        }

        try databaseManager.dbQueue.write { db in
            let templateRows = try Row.fetchAll(
                db,
                sql: "SELECT id FROM recurring_templates WHERE wallet_id = ? OR counterparty_wallet_id = ?",
                arguments: [id.uuidString, id.uuidString]
            )
            for row in templateRows {
                let templateID: String = row["id"]
                try db.execute(sql: "DELETE FROM recurring_instances WHERE template_id = ?", arguments: [templateID])
                try db.execute(sql: "DELETE FROM recurring_templates WHERE id = ?", arguments: [templateID])
            }

            try db.execute(sql: "DELETE FROM monthly_wallet_cashflow WHERE wallet_id = ?", arguments: [id.uuidString])
            try db.execute(sql: "DELETE FROM daily_wallet_balance_delta WHERE wallet_id = ?", arguments: [id.uuidString])
            try db.execute(sql: "DELETE FROM wallets WHERE id = ?", arguments: [id.uuidString])
            try rebuildFTS(db)
        }
    }

    public func saveCategory(_ category: Category) throws {
        try databaseManager.dbQueue.write { db in
            try db.execute(
                sql: """
                INSERT INTO categories (id, name, kind, icon_name, color_hex, parent_id, is_system, is_archived, sort_order, created_at, updated_at)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                ON CONFLICT(id) DO UPDATE SET
                    name = excluded.name,
                    kind = excluded.kind,
                    icon_name = excluded.icon_name,
                    color_hex = excluded.color_hex,
                    parent_id = excluded.parent_id,
                    is_archived = excluded.is_archived,
                    sort_order = excluded.sort_order,
                    updated_at = excluded.updated_at
                """,
                arguments: [
                    category.id.uuidString, category.name, category.kind.rawValue, category.iconName, category.colorHex,
                    category.parentID?.uuidString, category.isSystem, category.isArchived, category.sortOrder,
                    category.createdAt, category.updatedAt,
                ]
            )
        }
    }

    public func saveLabel(_ label: Label) throws {
        try databaseManager.dbQueue.write { db in
            try db.execute(
                sql: """
                INSERT INTO labels (id, name, color_hex, created_at, updated_at)
                VALUES (?, ?, ?, ?, ?)
                ON CONFLICT(id) DO UPDATE SET
                    name = excluded.name,
                    color_hex = excluded.color_hex,
                    updated_at = excluded.updated_at
                """,
                arguments: [label.id.uuidString, label.name, label.colorHex, label.createdAt, label.updatedAt]
            )
        }
    }

    public func saveBudget(_ budget: Budget) throws {
        guard budget.limitMinor > 0 else {
            throw CashRunwayError.validation("Budget limit must be greater than zero.")
        }

        try databaseManager.dbQueue.write { db in
            try db.execute(
                sql: """
                INSERT INTO budgets (id, category_id, month_key, limit_minor, is_archived, created_at, updated_at)
                VALUES (?, ?, ?, ?, ?, ?, ?)
                ON CONFLICT(id) DO UPDATE SET
                    category_id = excluded.category_id,
                    month_key = excluded.month_key,
                    limit_minor = excluded.limit_minor,
                    is_archived = excluded.is_archived,
                    updated_at = excluded.updated_at
                """,
                arguments: [
                    budget.id.uuidString, budget.categoryID.uuidString, budget.monthKey, budget.limitMinor,
                    budget.isArchived, budget.createdAt, budget.updatedAt,
                ]
            )
            try recomputeBudgetSnapshots(db, monthKeys: [budget.monthKey])
        }
    }

    public func saveRecurringTemplate(_ template: RecurringTemplate) throws {
        try databaseManager.dbQueue.write { db in
            try db.execute(
                sql: """
                INSERT INTO recurring_templates (id, kind, wallet_id, counterparty_wallet_id, amount_minor, category_id, merchant, note, rule_type, rule_interval, day_of_month, weekday, start_date, end_date, is_active, created_at, updated_at)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                ON CONFLICT(id) DO UPDATE SET
                    kind = excluded.kind,
                    wallet_id = excluded.wallet_id,
                    counterparty_wallet_id = excluded.counterparty_wallet_id,
                    amount_minor = excluded.amount_minor,
                    category_id = excluded.category_id,
                    merchant = excluded.merchant,
                    note = excluded.note,
                    rule_type = excluded.rule_type,
                    rule_interval = excluded.rule_interval,
                    day_of_month = excluded.day_of_month,
                    weekday = excluded.weekday,
                    start_date = excluded.start_date,
                    end_date = excluded.end_date,
                    is_active = excluded.is_active,
                    updated_at = excluded.updated_at
                """,
                arguments: [
                    template.id.uuidString, template.kind.rawValue, template.walletID.uuidString,
                    template.counterpartyWalletID?.uuidString, template.amountMinor, template.categoryID?.uuidString,
                    template.merchant, template.note, template.ruleType.rawValue, template.ruleInterval,
                    template.dayOfMonth, template.weekday, template.startDate, template.endDate, template.isActive,
                    template.createdAt, template.updatedAt,
                ]
            )
            try refreshRecurringInstances(db)
        }
    }

    public func saveRecurringInstance(_ instance: RecurringInstance) throws {
        try databaseManager.dbQueue.write { db in
            try db.execute(
                sql: """
                UPDATE recurring_instances
                SET due_date = ?, day_key = ?, status = ?, linked_transaction_id = ?, override_amount_minor = ?, override_category_id = ?, override_note = ?, override_merchant = ?, updated_at = ?
                WHERE id = ?
                """,
                arguments: [
                    instance.dueDate,
                    instance.dayKey,
                    instance.status.rawValue,
                    instance.linkedTransactionID?.uuidString,
                    instance.overrideAmountMinor,
                    instance.overrideCategoryID?.uuidString,
                    instance.overrideNote,
                    instance.overrideMerchant,
                    instance.updatedAt,
                    instance.id.uuidString,
                ]
            )
        }
    }

    public func dashboard(monthKey: Int, walletID: UUID? = nil) throws -> DashboardSnapshot {
        try databaseManager.dbQueue.read { db in
            let totalBalanceMinor: Int64
            if let walletID {
                totalBalanceMinor = try Int64.fetchOne(db, sql: "SELECT current_balance_minor FROM wallets WHERE id = ?", arguments: [walletID.uuidString]) ?? 0
            } else {
                totalBalanceMinor = try Int64.fetchOne(db, sql: "SELECT COALESCE(SUM(current_balance_minor), 0) FROM wallets WHERE is_archived = 0") ?? 0
            }

            let monthCashflowRows = try Row.fetchAll(
                db,
                sql: """
                SELECT income_minor, expense_minor, transfer_in_minor, transfer_out_minor
                FROM monthly_wallet_cashflow
                WHERE month_key = ?
                \(walletID == nil ? "" : "AND wallet_id = ?")
                """,
                arguments: walletID == nil ? [monthKey] : [monthKey, walletID!.uuidString]
            )

            let monthIncomeMinor = monthCashflowRows.reduce(into: Int64.zero) { $0 += $1["income_minor"] }
            let monthExpenseMinor = monthCashflowRows.reduce(into: Int64.zero) { $0 += $1["expense_minor"] }
            let monthNetMinor = monthIncomeMinor - monthExpenseMinor

            let categoryRows = try Row.fetchAll(
                db,
                sql: """
                SELECT c.id, c.name, c.color_hex, c.icon_name, m.expense_minor, m.txn_count
                FROM monthly_category_spend m
                JOIN categories c ON c.id = m.category_id
                WHERE m.month_key = ?
                ORDER BY m.expense_minor DESC
                LIMIT 8
                """,
                arguments: [monthKey]
            )
            let totalExpense = max(monthExpenseMinor, 1)
            let categories = categoryRows.map { row in
                let amountMinor: Int64 = row["expense_minor"]
                return DashboardCategorySlice(
                    id: UUID(uuidString: row["id"])!,
                    name: row["name"],
                    colorHex: row["color_hex"],
                    iconName: row["icon_name"],
                    amountMinor: amountMinor,
                    transactionCount: row["txn_count"],
                    percentage: Double(amountMinor) / Double(totalExpense)
                )
            }

            let historyRows = try Row.fetchAll(
                db,
                sql: """
                SELECT day_key, COALESCE(SUM(net_delta_minor), 0) AS total
                FROM daily_wallet_balance_delta
                WHERE day_key BETWEEN ? AND ?
                GROUP BY day_key
                ORDER BY day_key
                """,
                arguments: [monthKey * 100 + 1, monthKey * 100 + 31]
            )
            var rollingBalance = totalBalanceMinor - historyRows.reduce(into: Int64.zero) { $0 += $1["total"] }
            let wealthHistory = historyRows.map { row -> BalancePoint in
                rollingBalance += row["total"]
                return BalancePoint(dayKey: row["day_key"], amountMinor: rollingBalance)
            }

            let recentTransactions = try listTransactions(db, query: .init(walletID: walletID))

            return DashboardSnapshot(
                monthKey: monthKey,
                walletFilterID: walletID,
                totalBalanceMinor: totalBalanceMinor,
                monthIncomeMinor: monthIncomeMinor,
                monthExpenseMinor: monthExpenseMinor,
                monthNetMinor: monthNetMinor,
                wealthHistory: wealthHistory,
                categories: categories,
                recentTransactions: Array(recentTransactions.prefix(8))
            )
        }
    }

    public func timelineSnapshot(monthKey: Int, walletID: UUID? = nil, query: TransactionQuery = .init(), period: TimelinePeriod = .month) throws -> TimelineSnapshot {
        try databaseManager.dbQueue.read { db in
            let effectiveWalletID = walletID ?? query.walletID
            let bars = try Self.loadBars(db, monthKey: monthKey, walletID: effectiveWalletID, period: period)
            let anchorPeriodKey = Self.anchorPeriodKey(monthKey: monthKey, period: period)

            var scopedQuery = query
            scopedQuery.walletID = effectiveWalletID
            Self.applyPeriodScope(&scopedQuery, period: period, periodKey: anchorPeriodKey)
            let items = try listTransactions(db, query: scopedQuery, limit: nil)
            let sections = Dictionary(grouping: items, by: \.dayKey)
                .map { key, values in
                    TimelineSection(
                        periodKey: key,
                        periodLabel: DateKeys.dayLabel(for: key),
                        totalMinor: values.reduce(into: Int64.zero) { $0 += $1.amountMinor },
                        items: values
                    )
                }
                .sorted { $0.periodKey > $1.periodKey }

            let selectedBar = bars.first(where: { $0.periodKey == anchorPeriodKey }) ?? bars.last
            let heroCashFlow = selectedBar.map { $0.incomeMinor - $0.expenseMinor } ?? 0
            return TimelineSnapshot(
                anchorMonthKey: monthKey,
                walletFilterID: effectiveWalletID,
                heroCashFlowMinor: heroCashFlow,
                bars: bars,
                sections: sections,
                period: period
            )
        }
    }

    private static func anchorPeriodKey(monthKey: Int, period: TimelinePeriod) -> Int {
        let anchorDate = DateKeys.startOfMonth(for: monthKey)
        return DateKeys.periodKey(for: anchorDate, period: period)
    }

    private static func loadBars(_ db: Database, monthKey: Int, walletID: UUID?, period: TimelinePeriod) throws -> [TimelineBarPoint] {
        switch period {
        case .month:
            return try loadMonthlyBars(db, monthKey: monthKey, walletID: walletID)
        case .year:
            return try loadYearlyBars(db, monthKey: monthKey, walletID: walletID)
        }
    }

    private static func loadMonthlyBars(_ db: Database, monthKey: Int, walletID: UUID?) throws -> [TimelineBarPoint] {
        let months = Self.monthWindow(endingAt: monthKey, count: 6)
        var conditions = ["month_key BETWEEN ? AND ?"]
        var arguments: [any DatabaseValueConvertible] = [months.first ?? monthKey, months.last ?? monthKey]
        if let walletID {
            conditions.append("wallet_id = ?")
            arguments.append(walletID.uuidString)
        }
        let rows = try Row.fetchAll(
            db,
            sql: """
            SELECT month_key,
                   COALESCE(SUM(income_minor), 0) AS income_minor,
                   COALESCE(SUM(expense_minor), 0) AS expense_minor
            FROM monthly_wallet_cashflow
            WHERE \(conditions.joined(separator: " AND "))
            GROUP BY month_key
            ORDER BY month_key
            """,
            arguments: StatementArguments(arguments)
        )
        let byMonth = Dictionary(uniqueKeysWithValues: rows.map { row in
            let month: Int = row["month_key"]
            return (
                month,
                TimelineBarPoint(
                    periodKey: month,
                    incomeMinor: row["income_minor"],
                    expenseMinor: row["expense_minor"],
                    xLabel: monthAbbreviation(for: month)
                )
            )
        })
        return months.map { month in
            byMonth[month] ?? TimelineBarPoint(periodKey: month, incomeMinor: 0, expenseMinor: 0, xLabel: monthAbbreviation(for: month))
        }
    }

    private static func loadYearlyBars(_ db: Database, monthKey: Int, walletID: UUID?) throws -> [TimelineBarPoint] {
        let year = monthKey / 100
        let years = Self.yearWindow(endingAt: year, count: 6)
        let startMonth = (year - 5) * 100 + 1
        let endMonth = year * 100 + 12
        var conditions = ["month_key BETWEEN ? AND ?"]
        var arguments: [any DatabaseValueConvertible] = [startMonth, endMonth]
        if let walletID {
            conditions.append("wallet_id = ?")
            arguments.append(walletID.uuidString)
        }
        let rows = try Row.fetchAll(
            db,
            sql: """
            SELECT month_key,
                   COALESCE(SUM(income_minor), 0) AS income_minor,
                   COALESCE(SUM(expense_minor), 0) AS expense_minor
            FROM monthly_wallet_cashflow
            WHERE \(conditions.joined(separator: " AND "))
            GROUP BY month_key
            ORDER BY month_key
            """,
            arguments: StatementArguments(arguments)
        )
        var byYear: [Int: (income: Int64, expense: Int64)] = [:]
        for row in rows {
            let month: Int = row["month_key"]
            let y = month / 100
            var current = byYear[y] ?? (0, 0)
            current.income += row["income_minor"]
            current.expense += row["expense_minor"]
            byYear[y] = current
        }
        return years.map { y in
            let values = byYear[y] ?? (0, 0)
            return TimelineBarPoint(
                periodKey: y,
                incomeMinor: values.income,
                expenseMinor: values.expense,
                xLabel: "\(y)"
            )
        }
    }

    private static func applyPeriodScope(_ query: inout TransactionQuery, period: TimelinePeriod, periodKey: Int) {
        let bounds = periodDateBounds(period: period, periodKey: periodKey)
        if let startDate = query.startDate {
            query.startDate = max(startDate, bounds.start)
        } else {
            query.startDate = bounds.start
        }
        if let endDate = query.endDate {
            query.endDate = min(endDate, bounds.end)
        } else {
            query.endDate = bounds.end
        }
    }

    private static func periodDateBounds(period: TimelinePeriod, periodKey: Int) -> (start: Date, end: Date) {
        switch period {
        case .month:
            return (DateKeys.startOfMonth(for: periodKey), endOfMonth(for: periodKey))
        case .year:
            let startMonthKey = periodKey * 100 + 1
            let endMonthKey = periodKey * 100 + 12
            return (DateKeys.startOfMonth(for: startMonthKey), endOfMonth(for: endMonthKey))
        }
    }

    private static func monthAbbreviation(for monthKey: Int) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "MMM"
        return formatter.string(from: DateKeys.startOfMonth(for: monthKey))
    }

    public func overviewSnapshot(monthKey: Int, walletID: UUID? = nil) throws -> OverviewSnapshot {
        try databaseManager.dbQueue.read { db in
            let months = Self.monthWindow(endingAt: monthKey, count: 6)
            let cashflowRows = try Row.fetchAll(
                db,
                sql: """
                SELECT month_key,
                       COALESCE(SUM(income_minor), 0) AS income_minor,
                       COALESCE(SUM(expense_minor), 0) AS expense_minor
                FROM monthly_wallet_cashflow
                WHERE month_key BETWEEN ? AND ?
                \(walletID == nil ? "" : "AND wallet_id = ?")
                GROUP BY month_key
                ORDER BY month_key
                """,
                arguments: walletID == nil
                    ? [months.first ?? monthKey, months.last ?? monthKey]
                    : [months.first ?? monthKey, months.last ?? monthKey, walletID!.uuidString]
            )
            let cashflowByMonth = Dictionary(uniqueKeysWithValues: cashflowRows.map { row in
                let month: Int = row["month_key"]
                return (month, (income: row["income_minor"] as Int64, expense: row["expense_minor"] as Int64))
            })

            let monthPoints = try months.map { month in
                let values = cashflowByMonth[month] ?? (income: Int64.zero, expense: Int64.zero)
                return OverviewMonthPoint(
                    monthKey: month,
                    totalWealthMinor: try self.balance(atEndOfMonth: month, walletID: walletID, db: db),
                    cashFlowMinor: values.income - values.expense,
                    incomeMinor: values.income,
                    expenseMinor: values.expense
                )
            }

            let selectedPoint: OverviewMonthPoint
            if let existingPoint = monthPoints.first(where: { $0.monthKey == monthKey }) {
                selectedPoint = existingPoint
            } else {
                selectedPoint = OverviewMonthPoint(
                    monthKey: monthKey,
                    totalWealthMinor: try balance(atEndOfMonth: monthKey, walletID: walletID, db: db),
                    cashFlowMinor: 0,
                    incomeMinor: 0,
                    expenseMinor: 0
                )
            }

            let categoryRows = try Row.fetchAll(
                db,
                sql: """
                SELECT c.id, c.name, c.kind, c.color_hex, c.icon_name,
                       COALESCE(SUM(t.amount_minor), 0) AS expense_minor,
                       COUNT(t.id) AS txn_count
                FROM categories c
                LEFT JOIN transactions t
                  ON t.category_id = c.id
                 AND t.is_deleted = 0
                 AND (
                    (c.kind = 'expense' AND t.type = 'expense')
                    OR
                    (c.kind = 'income' AND t.type = 'income')
                 )
                 AND t.local_month_key = ?
                 \(walletID == nil ? "" : "AND t.wallet_id = ?")
                WHERE c.kind IN ('expense', 'income')
                GROUP BY c.id
                HAVING expense_minor > 0
                ORDER BY c.kind, expense_minor DESC, c.sort_order, c.name
                """,
                arguments: walletID == nil ? [monthKey] : [monthKey, walletID!.uuidString]
            )
            let totalExpense = max(selectedPoint.expenseMinor, 1)
            let totalIncome = max(selectedPoint.incomeMinor, 1)
            let categories = categoryRows.map { row in
                let amountMinor: Int64 = row["expense_minor"]
                let kind = CategoryKind(rawValue: row["kind"]) ?? .expense
                return OverviewCategoryRow(
                    id: UUID(uuidString: row["id"])!,
                    name: row["name"],
                    kind: kind,
                    colorHex: row["color_hex"],
                    iconName: row["icon_name"],
                    amountMinor: amountMinor,
                    transactionCount: row["txn_count"],
                    percentage: Double(amountMinor) / Double(kind == .expense ? totalExpense : totalIncome)
                )
            }

            let labelRows = try Row.fetchAll(
                db,
                sql: """
                SELECT l.id, l.name, l.color_hex,
                       CASE t.type WHEN 'income' THEN 'income' ELSE 'expense' END AS kind,
                       COALESCE(SUM(t.amount_minor), 0) AS label_minor,
                       COUNT(DISTINCT t.id) AS txn_count
                FROM labels l
                JOIN transaction_labels tl ON tl.label_id = l.id
                JOIN transactions t ON t.id = tl.transaction_id
                WHERE t.is_deleted = 0
                  AND t.type IN ('expense', 'income')
                  AND t.local_month_key = ?
                  \(walletID == nil ? "" : "AND t.wallet_id = ?")
                GROUP BY l.id, kind
                HAVING label_minor > 0
                ORDER BY kind, label_minor DESC, l.name
                """,
                arguments: walletID == nil ? [monthKey] : [monthKey, walletID!.uuidString]
            )
            let labels = labelRows.map { row in
                let amountMinor: Int64 = row["label_minor"]
                let kind = CategoryKind(rawValue: row["kind"]) ?? .expense
                return OverviewLabelRow(
                    labelID: UUID(uuidString: row["id"])!,
                    name: row["name"],
                    kind: kind,
                    colorHex: row["color_hex"],
                    amountMinor: amountMinor,
                    transactionCount: row["txn_count"],
                    percentage: Double(amountMinor) / Double(kind == .expense ? totalExpense : totalIncome)
                )
            }

            return OverviewSnapshot(
                selectedMonthKey: monthKey,
                walletFilterID: walletID,
                months: monthPoints,
                totalWealthMinor: selectedPoint.totalWealthMinor,
                monthCashFlowMinor: selectedPoint.cashFlowMinor,
                monthIncomeMinor: selectedPoint.incomeMinor,
                monthExpenseMinor: selectedPoint.expenseMinor,
                categories: categories,
                labels: labels
            )
        }
    }

    public func categoryManagementItems(kind: CategoryKind) throws -> [CategoryManagementItem] {
        try databaseManager.dbQueue.read { db in
            try Row.fetchAll(
                db,
                sql: """
                SELECT c.*,
                       COUNT(DISTINCT t.id) AS txn_count,
                       COUNT(DISTINCT t.wallet_id) AS wallet_count
                FROM categories c
                LEFT JOIN transactions t
                  ON t.category_id = c.id
                 AND t.is_deleted = 0
                 AND t.type != 'transfer_in'
                WHERE c.kind = ?
                GROUP BY c.id
                ORDER BY c.sort_order, c.name
                """,
                arguments: [kind.rawValue]
            ).map { row in
                let category = try Self.category(row)
                return CategoryManagementItem(
                    category: category,
                    transactionCount: row["txn_count"],
                    walletCount: row["wallet_count"],
                    isVisible: !category.isArchived
                )
            }
        }
    }

    public func reorderCategories(kind: CategoryKind, orderedCategoryIDs: [UUID]) throws {
        try databaseManager.dbQueue.write { db in
            for (index, id) in orderedCategoryIDs.enumerated() {
                try db.execute(
                    sql: "UPDATE categories SET sort_order = ?, updated_at = ? WHERE id = ? AND kind = ?",
                    arguments: [index, Date.now, id.uuidString, kind.rawValue]
                )
            }
        }
    }

    public func transactions(query: TransactionQuery = .init(), limit: Int? = 300) throws -> [TransactionListItem] {
        try databaseManager.dbQueue.read { db in
            try listTransactions(db, query: query, limit: limit)
        }
    }

    public func transactionDraft(id: UUID) throws -> TransactionDraft {
        try databaseManager.dbQueue.read { db in
            guard let row = try Row.fetchOne(db, sql: "SELECT * FROM transactions WHERE id = ?", arguments: [id.uuidString]) else {
                throw CashRunwayError.notFound
            }
            let transaction = try Self.transaction(row)
            let labelRows = try Row.fetchAll(
                db,
                sql: """
                SELECT label_id FROM transaction_labels WHERE transaction_id = ?
                UNION ALL
                SELECT label_id FROM transaction_labels WHERE transaction_id = ?
                """,
                arguments: [id.uuidString, transaction.linkedTransferID?.uuidString]
            )
            let labelIDs = labelRows.compactMap { UUID(uuidString: $0["label_id"]) }

            if transaction.type == .transferOut {
                guard let linkedID = transaction.linkedTransferID,
                      let destinationWalletID = try String.fetchOne(db, sql: "SELECT wallet_id FROM transactions WHERE id = ?", arguments: [linkedID.uuidString]).flatMap(UUID.init(uuidString:))
                else {
                    throw CashRunwayError.invalidState("Transfer pair is missing.")
                }
                return TransactionDraft(
                    id: transaction.id,
                    kind: .transfer,
                    walletID: transaction.walletID,
                    destinationWalletID: destinationWalletID,
                    amountMinor: transaction.amountMinor,
                    occurredAt: transaction.occurredAt,
                    labelIDs: labelIDs,
                    merchant: transaction.merchant ?? "",
                    note: transaction.note ?? "",
                    source: transaction.source,
                    recurringTemplateID: transaction.recurringTemplateID,
                    recurringInstanceID: transaction.recurringInstanceID
                )
            }

            return TransactionDraft(
                id: transaction.id,
                kind: transaction.type == .expense ? .expense : .income,
                walletID: transaction.walletID,
                amountMinor: transaction.amountMinor,
                occurredAt: transaction.occurredAt,
                categoryID: transaction.categoryID,
                labelIDs: labelIDs,
                merchant: transaction.merchant ?? "",
                note: transaction.note ?? "",
                source: transaction.source,
                recurringTemplateID: transaction.recurringTemplateID,
                recurringInstanceID: transaction.recurringInstanceID
            )
        }
    }

    public func saveTransaction(_ draft: TransactionDraft) throws {
        try validate(draft)
        try databaseManager.dbQueue.write { db in
            if draft.kind == .transfer {
                try saveTransfer(db, draft: draft)
            } else {
                try saveSingleTransaction(db, draft: draft)
            }
        }
    }

    public func deleteTransaction(id: UUID) throws {
        try databaseManager.dbQueue.write { db in
            guard let transactionRow = try Row.fetchOne(db, sql: "SELECT * FROM transactions WHERE id = ?", arguments: [id.uuidString]) else {
                throw CashRunwayError.notFound
            }
            let transaction = try Self.transaction(transactionRow)

            var transactionsToDelete = [transaction]
            if transaction.type == .transferOut, let linkedID = transaction.linkedTransferID,
               let linkedRow = try Row.fetchOne(db, sql: "SELECT * FROM transactions WHERE id = ?", arguments: [linkedID.uuidString]) {
                transactionsToDelete.append(try Self.transaction(linkedRow))
            }

            for item in transactionsToDelete {
                try applyContribution(db, old: contribution(for: item), new: nil)
                try db.execute(sql: "DELETE FROM transaction_labels WHERE transaction_id = ?", arguments: [item.id.uuidString])
                try db.execute(sql: "DELETE FROM transaction_search WHERE transaction_id = ?", arguments: [item.id.uuidString])
                try db.execute(sql: "DELETE FROM transactions WHERE id = ?", arguments: [item.id.uuidString])
            }
        }
    }

    public func mergeCategory(oldCategoryID: UUID, into newCategoryID: UUID) throws {
        try databaseManager.dbQueue.write { db in
            let now = Date()
            let affectedMonths = Set(try Int.fetchAll(
                db,
                sql: "SELECT DISTINCT local_month_key FROM transactions WHERE category_id = ?",
                arguments: [oldCategoryID.uuidString]
            ))
            try db.execute(
                sql: "UPDATE transactions SET category_id = ?, updated_at = ? WHERE category_id = ?",
                arguments: [newCategoryID.uuidString, now, oldCategoryID.uuidString]
            )
            try db.execute(
                sql: """
                INSERT INTO category_remaps (id, old_category_id, new_category_id, remapped_at)
                VALUES (?, ?, ?, ?)
                """,
                arguments: [UUID().uuidString, oldCategoryID.uuidString, newCategoryID.uuidString, now]
            )
            try db.execute(
                sql: """
                INSERT INTO audit_entries (id, entity_type, entity_id, operation, diff_json, created_at)
                VALUES (?, 'category', ?, 'remap', ?, ?)
                """,
                arguments: [UUID().uuidString, oldCategoryID.uuidString, "{\"from\":\"\(oldCategoryID.uuidString)\",\"to\":\"\(newCategoryID.uuidString)\"}", now]
            )
            try markDirtyRanges(db, monthKeys: affectedMonths)
            try processPendingAggregateRebuilds(db)
            try rebuildFTS(db)
        }
    }

    public func appendImportedTransactions(_ drafts: [TransactionDraft]) throws {
        guard !drafts.isEmpty else { return }
        try databaseManager.dbQueue.write { db in
            for draft in drafts {
                try validate(draft)
                if draft.kind == .transfer {
                    try saveTransfer(db, draft: draft, updateDerivedData: false)
                } else {
                    try saveSingleTransaction(db, draft: draft, updateDerivedData: false)
                }
            }
        }
    }

    public func finalizeImport(jobID: UUID, affectedMonths: Set<Int>, validRows: Int, invalidRows: Int, errorSummary: String?) throws {
        try databaseManager.dbQueue.write { db in
            try markDirtyRanges(db, monthKeys: affectedMonths)
            try processPendingAggregateRebuilds(db)
            try rebuildFTS(db)
            try db.execute(
                sql: """
                UPDATE import_jobs
                SET status = ?, valid_rows = ?, invalid_rows = ?, finished_at = ?, error_summary = ?
                WHERE id = ?
                """,
                arguments: [
                    ImportJobStatus.committed.rawValue,
                    validRows,
                    invalidRows,
                    Date(),
                    errorSummary,
                    jobID.uuidString,
                ]
            )
        }
    }

    public func failImport(jobID: UUID, errorSummary: String) throws {
        try databaseManager.dbQueue.write { db in
            try db.execute(
                sql: "UPDATE import_jobs SET status = ?, finished_at = ?, error_summary = ? WHERE id = ?",
                arguments: [ImportJobStatus.failed.rawValue, Date(), errorSummary, jobID.uuidString]
            )
        }
    }

    public func runMaintenance() throws {
        try databaseManager.dbQueue.write { db in
            try processPendingAggregateRebuilds(db)
        }
    }

    public func refreshRecurringInstances() throws {
        try databaseManager.dbQueue.write { db in
            try refreshRecurringInstances(db)
        }
    }

    public func postRecurringInstance(id: UUID, on date: Date = .now) throws {
        try databaseManager.dbQueue.write { db in
            guard let row = try Row.fetchOne(db, sql: "SELECT * FROM recurring_instances WHERE id = ?", arguments: [id.uuidString]) else {
                throw CashRunwayError.notFound
            }
            let instance = try Self.recurringInstance(row)
            guard let templateRow = try Row.fetchOne(db, sql: "SELECT * FROM recurring_templates WHERE id = ?", arguments: [instance.templateID.uuidString]) else {
                throw CashRunwayError.notFound
            }
            let template = try Self.recurringTemplate(templateRow)
            let linkedTransactionID = UUID()

            let draft = TransactionDraft(
                id: linkedTransactionID,
                kind: template.kind == .transfer ? .transfer : (template.kind == .expense ? .expense : .income),
                walletID: template.walletID,
                destinationWalletID: template.counterpartyWalletID,
                amountMinor: instance.overrideAmountMinor ?? template.amountMinor,
                occurredAt: date,
                categoryID: instance.overrideCategoryID ?? template.categoryID,
                merchant: instance.overrideMerchant ?? template.merchant ?? "",
                note: instance.overrideNote ?? template.note ?? "",
                source: .recurring,
                recurringTemplateID: template.id,
                recurringInstanceID: instance.id
            )
            try draft.kind == .transfer ? saveTransfer(db, draft: draft) : saveSingleTransaction(db, draft: draft)
            try db.execute(
                sql: "UPDATE recurring_instances SET status = ?, linked_transaction_id = ?, updated_at = ? WHERE id = ?",
                arguments: [RecurringInstanceStatus.posted.rawValue, linkedTransactionID.uuidString, Date(), id.uuidString]
            )
        }
    }

    public func skipRecurringInstance(id: UUID) throws {
        try databaseManager.dbQueue.write { db in
            try db.execute(
                sql: "UPDATE recurring_instances SET status = ?, updated_at = ? WHERE id = ?",
                arguments: [RecurringInstanceStatus.skipped.rawValue, Date(), id.uuidString]
            )
        }
    }

    private func saveSingleTransaction(_ db: Database, draft: TransactionDraft, updateDerivedData: Bool = true) throws {
        let now = Date()
        let id = draft.id ?? UUID()
        let existing: CashRunwayTransaction? = if let draftID = draft.id {
            try existingTransaction(db, id: draftID)
        } else {
            nil
        }
        let cashRunwayType: TransactionKind = draft.kind == .expense ? .expense : .income
        let record = CashRunwayTransaction(
            id: id,
            walletID: draft.walletID,
            type: cashRunwayType,
            linkedTransferID: nil,
            amountMinor: draft.amountMinor,
            occurredAt: draft.occurredAt,
            localDayKey: DateKeys.dayKey(for: draft.occurredAt),
            localMonthKey: DateKeys.monthKey(for: draft.occurredAt),
            categoryID: draft.categoryID,
            merchant: draft.merchant.isEmpty ? nil : draft.merchant,
            note: draft.note.isEmpty ? nil : draft.note,
            isDeleted: false,
            source: draft.source,
            recurringTemplateID: draft.recurringTemplateID,
            recurringInstanceID: draft.recurringInstanceID,
            createdAt: existing?.createdAt ?? now,
            updatedAt: now
        )

        if updateDerivedData {
            try applyContribution(db, old: existing.map(contribution(for:)), new: contribution(for: record))
        }
        try upsertTransactionRow(db, transaction: record)
        try syncLabels(db, transactionID: id, labelIDs: draft.labelIDs)
        if updateDerivedData {
            try syncSearch(db, transaction: record)
        }
    }

    private func saveTransfer(_ db: Database, draft: TransactionDraft, updateDerivedData: Bool = true) throws {
        guard let destinationWalletID = draft.destinationWalletID, destinationWalletID != draft.walletID else {
            throw CashRunwayError.validation("Transfer requires two different wallets.")
        }
        let now = Date()
        let sourceID = draft.id ?? UUID()
        let sourceExisting: CashRunwayTransaction? = if let draftID = draft.id {
            try existingTransaction(db, id: draftID)
        } else {
            nil
        }
        let targetExisting: CashRunwayTransaction? = if let linkedTransferID = sourceExisting?.linkedTransferID {
            try existingTransaction(db, id: linkedTransferID)
        } else {
            nil
        }
        let targetID = sourceExisting?.linkedTransferID ?? UUID()

        let sourceRecord = CashRunwayTransaction(
            id: sourceID,
            walletID: draft.walletID,
            type: .transferOut,
            linkedTransferID: targetID,
            amountMinor: draft.amountMinor,
            occurredAt: draft.occurredAt,
            localDayKey: DateKeys.dayKey(for: draft.occurredAt),
            localMonthKey: DateKeys.monthKey(for: draft.occurredAt),
            categoryID: nil,
            merchant: draft.merchant.isEmpty ? nil : draft.merchant,
            note: draft.note.isEmpty ? nil : draft.note,
            isDeleted: false,
            source: draft.source,
            recurringTemplateID: draft.recurringTemplateID,
            recurringInstanceID: draft.recurringInstanceID,
            createdAt: sourceExisting?.createdAt ?? now,
            updatedAt: now
        )
        let targetRecord = CashRunwayTransaction(
            id: targetID,
            walletID: destinationWalletID,
            type: .transferIn,
            linkedTransferID: sourceID,
            amountMinor: draft.amountMinor,
            occurredAt: draft.occurredAt,
            localDayKey: DateKeys.dayKey(for: draft.occurredAt),
            localMonthKey: DateKeys.monthKey(for: draft.occurredAt),
            categoryID: nil,
            merchant: draft.merchant.isEmpty ? nil : draft.merchant,
            note: draft.note.isEmpty ? nil : draft.note,
            isDeleted: false,
            source: draft.source,
            recurringTemplateID: draft.recurringTemplateID,
            recurringInstanceID: draft.recurringInstanceID,
            createdAt: targetExisting?.createdAt ?? now,
            updatedAt: now
        )

        if updateDerivedData {
            try applyContribution(db, old: sourceExisting.map(contribution(for:)), new: contribution(for: sourceRecord))
            try applyContribution(db, old: targetExisting.map(contribution(for:)), new: contribution(for: targetRecord))
        }
        try upsertTransactionRow(db, transaction: sourceRecord)
        try upsertTransactionRow(db, transaction: targetRecord)
        try syncLabels(db, transactionID: sourceID, labelIDs: draft.labelIDs)
        try syncLabels(db, transactionID: targetID, labelIDs: draft.labelIDs)
        if updateDerivedData {
            try syncSearch(db, transaction: sourceRecord)
            try syncSearch(db, transaction: targetRecord)
        }
    }

    private func existingTransaction(_ db: Database, id: UUID) throws -> CashRunwayTransaction? {
        guard let row = try Row.fetchOne(db, sql: "SELECT * FROM transactions WHERE id = ?", arguments: [id.uuidString]) else {
            return nil
        }
        return try Self.transaction(row)
    }

    private func upsertTransactionRow(_ db: Database, transaction: CashRunwayTransaction) throws {
        try db.execute(
            sql: """
            INSERT INTO transactions (id, wallet_id, type, linked_transfer_id, amount_minor, occurred_at, local_day_key, local_month_key, category_id, merchant, note, is_deleted, source, recurring_template_id, recurring_instance_id, created_at, updated_at)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            ON CONFLICT(id) DO UPDATE SET
                wallet_id = excluded.wallet_id,
                type = excluded.type,
                linked_transfer_id = excluded.linked_transfer_id,
                amount_minor = excluded.amount_minor,
                occurred_at = excluded.occurred_at,
                local_day_key = excluded.local_day_key,
                local_month_key = excluded.local_month_key,
                category_id = excluded.category_id,
                merchant = excluded.merchant,
                note = excluded.note,
                source = excluded.source,
                recurring_template_id = excluded.recurring_template_id,
                recurring_instance_id = excluded.recurring_instance_id,
                updated_at = excluded.updated_at
            """,
            arguments: [
                transaction.id.uuidString, transaction.walletID.uuidString, transaction.type.rawValue, transaction.linkedTransferID?.uuidString,
                transaction.amountMinor, transaction.occurredAt, transaction.localDayKey, transaction.localMonthKey,
                transaction.categoryID?.uuidString, transaction.merchant, transaction.note, transaction.isDeleted,
                transaction.source.rawValue, transaction.recurringTemplateID?.uuidString, transaction.recurringInstanceID?.uuidString,
                transaction.createdAt, transaction.updatedAt,
            ]
        )
    }

    private func validate(_ draft: TransactionDraft) throws {
        guard draft.amountMinor > 0 else {
            throw CashRunwayError.validation("Amount must be greater than zero.")
        }
        if draft.kind != .transfer, draft.categoryID == nil {
            throw CashRunwayError.validation("Category is required for income and expense transactions.")
        }
    }

    private func syncLabels(_ db: Database, transactionID: UUID, labelIDs: [UUID]) throws {
        try db.execute(sql: "DELETE FROM transaction_labels WHERE transaction_id = ?", arguments: [transactionID.uuidString])
        for labelID in Array(Set(labelIDs)) {
            try db.execute(
                sql: "INSERT INTO transaction_labels (transaction_id, label_id) VALUES (?, ?)",
                arguments: [transactionID.uuidString, labelID.uuidString]
            )
        }
    }

    private func contribution(for transaction: CashRunwayTransaction) -> AggregateContribution {
        AggregateContribution(
            walletID: transaction.walletID,
            monthKey: transaction.localMonthKey,
            dayKey: transaction.localDayKey,
            type: transaction.type,
            amountMinor: transaction.amountMinor,
            categoryID: transaction.categoryID
        )
    }

    private func applyContribution(_ db: Database, old: AggregateContribution?, new: AggregateContribution?) throws {
        if let old {
            try mutateAggregate(db, contribution: old, multiplier: -1)
        }
        if let new {
            try mutateAggregate(db, contribution: new, multiplier: 1)
        }
        let impactedMonthKeys = Set([old?.monthKey, new?.monthKey].compactMap { $0 })
        try recomputeBudgetSnapshots(db, monthKeys: impactedMonthKeys)
    }

    private func mutateAggregate(_ db: Database, contribution: AggregateContribution, multiplier: Int64) throws {
        let amount = contribution.amountMinor * multiplier
        let now = Date()
        let (income, expense, transferIn, transferOut): (Int64, Int64, Int64, Int64) = switch contribution.type {
        case .expense: (0, amount, 0, 0)
        case .income: (amount, 0, 0, 0)
        case .transferIn: (0, 0, amount, 0)
        case .transferOut: (0, 0, 0, amount)
        }

        try db.execute(
            sql: """
            INSERT INTO monthly_wallet_cashflow (wallet_id, month_key, income_minor, expense_minor, transfer_in_minor, transfer_out_minor, txn_count, updated_at)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?)
            ON CONFLICT(wallet_id, month_key) DO UPDATE SET
                income_minor = income_minor + excluded.income_minor,
                expense_minor = expense_minor + excluded.expense_minor,
                transfer_in_minor = transfer_in_minor + excluded.transfer_in_minor,
                transfer_out_minor = transfer_out_minor + excluded.transfer_out_minor,
                txn_count = txn_count + excluded.txn_count,
                updated_at = excluded.updated_at
            """,
            arguments: [
                contribution.walletID.uuidString, contribution.monthKey, income, expense, transferIn, transferOut,
                multiplier, now,
            ]
        )

        if contribution.type == .expense, let categoryID = contribution.categoryID {
            try db.execute(
                sql: """
                INSERT INTO monthly_category_spend (category_id, month_key, expense_minor, txn_count, updated_at)
                VALUES (?, ?, ?, ?, ?)
                ON CONFLICT(category_id, month_key) DO UPDATE SET
                    expense_minor = expense_minor + excluded.expense_minor,
                    txn_count = txn_count + excluded.txn_count,
                    updated_at = excluded.updated_at
                """,
                arguments: [categoryID.uuidString, contribution.monthKey, amount, multiplier, now]
            )
            try db.execute(
                sql: "DELETE FROM monthly_category_spend WHERE category_id = ? AND month_key = ? AND expense_minor = 0 AND txn_count <= 0",
                arguments: [categoryID.uuidString, contribution.monthKey]
            )
        }

        try db.execute(
            sql: """
            INSERT INTO daily_wallet_balance_delta (wallet_id, day_key, net_delta_minor, updated_at)
            VALUES (?, ?, ?, ?)
            ON CONFLICT(wallet_id, day_key) DO UPDATE SET
                net_delta_minor = net_delta_minor + excluded.net_delta_minor,
                updated_at = excluded.updated_at
            """,
            arguments: [contribution.walletID.uuidString, contribution.dayKey, amount * contribution.type.walletDeltaSign, now]
        )
        try db.execute(
            sql: "DELETE FROM daily_wallet_balance_delta WHERE wallet_id = ? AND day_key = ? AND net_delta_minor = 0",
            arguments: [contribution.walletID.uuidString, contribution.dayKey]
        )
        try db.execute(
            sql: "UPDATE wallets SET current_balance_minor = current_balance_minor + ?, updated_at = ? WHERE id = ?",
            arguments: [amount * contribution.type.walletDeltaSign, now, contribution.walletID.uuidString]
        )
        try db.execute(
            sql: """
            DELETE FROM monthly_wallet_cashflow
            WHERE wallet_id = ? AND month_key = ? AND income_minor = 0 AND expense_minor = 0
              AND transfer_in_minor = 0 AND transfer_out_minor = 0 AND txn_count <= 0
            """,
            arguments: [contribution.walletID.uuidString, contribution.monthKey]
        )
    }

    private func recomputeBudgetSnapshots(_ db: Database, monthKeys: Set<Int>) throws {
        guard !monthKeys.isEmpty else { return }
        let now = Date()
        for monthKey in monthKeys {
            let rows = try Row.fetchAll(
                db,
                sql: """
                SELECT b.id, b.limit_minor, COALESCE(m.expense_minor, 0) AS spent_minor
                FROM budgets b
                LEFT JOIN monthly_category_spend m ON m.category_id = b.category_id AND m.month_key = b.month_key
                WHERE b.month_key = ? AND b.is_archived = 0
                """,
                arguments: [monthKey]
            )
            for row in rows {
                let budgetID: String = row["id"]
                let limitMinor: Int64 = row["limit_minor"]
                let spentMinor: Int64 = row["spent_minor"]
                let remainingMinor = limitMinor - spentMinor
                let percent = Int((spentMinor * 10_000) / max(limitMinor, 1))
                try db.execute(
                    sql: """
                    INSERT INTO budget_progress_snapshot (budget_id, month_key, spent_minor, remaining_minor, percent_used_bp, updated_at)
                    VALUES (?, ?, ?, ?, ?, ?)
                    ON CONFLICT(budget_id, month_key) DO UPDATE SET
                        spent_minor = excluded.spent_minor,
                        remaining_minor = excluded.remaining_minor,
                        percent_used_bp = excluded.percent_used_bp,
                        updated_at = excluded.updated_at
                    """,
                    arguments: [budgetID, monthKey, spentMinor, remainingMinor, percent, now]
                )
            }
        }
    }

    private func listTransactions(_ db: Database, query: TransactionQuery, limit: Int? = 300) throws -> [TransactionListItem] {
        var conditions = ["t.is_deleted = 0", "t.type != 'transfer_in'"]
        var arguments: [String: any DatabaseValueConvertible] = [:]

        if let walletID = query.walletID {
            conditions.append("t.wallet_id = :walletID")
            arguments["walletID"] = walletID.uuidString
        }
        if let categoryID = query.categoryID {
            conditions.append("t.category_id = :categoryID")
            arguments["categoryID"] = categoryID.uuidString
        }
        if let labelID = query.labelID {
            conditions.append("EXISTS (SELECT 1 FROM transaction_labels tl WHERE tl.transaction_id = t.id AND tl.label_id = :labelID)")
            arguments["labelID"] = labelID.uuidString
        }
        if !query.searchText.isEmpty {
            conditions.append("t.id IN (SELECT transaction_id FROM transaction_search WHERE transaction_search MATCH :search)")
            arguments["search"] = query.searchText + "*"
        }
        if let startDate = query.startDate {
            conditions.append("t.occurred_at >= :startDate")
            arguments["startDate"] = startDate
        }
        if let endDate = query.endDate {
            conditions.append("t.occurred_at <= :endDate")
            arguments["endDate"] = endDate
        }

        let allowedDBKinds = query.kinds.flatMap { kind -> [String] in
            switch kind {
            case .expense: [TransactionKind.expense.rawValue]
            case .income: [TransactionKind.income.rawValue]
            case .transfer: [TransactionKind.transferOut.rawValue]
            }
        }
        if allowedDBKinds.count != TransactionDraft.Kind.allCases.count {
            conditions.append("t.type IN (\(allowedDBKinds.enumerated().map { ":kind\($0.offset)" }.joined(separator: ", ")))")
            for (index, value) in allowedDBKinds.enumerated() {
                arguments["kind\(index)"] = value
            }
        }

        let sql = """
        SELECT t.*, w.name AS wallet_name, c.name AS category_name, c.color_hex AS category_color_hex, c.icon_name AS category_icon_name
        FROM transactions t
        JOIN wallets w ON w.id = t.wallet_id
        LEFT JOIN categories c ON c.id = t.category_id
        WHERE \(conditions.joined(separator: " AND "))
        ORDER BY t.occurred_at DESC, t.created_at DESC
        \(limit.map { "LIMIT \($0)" } ?? "")
        """

        return try Row.fetchAll(db, sql: sql, arguments: StatementArguments(arguments)).map { row in
            let transaction = try Self.transaction(row)
            let labelRows = try Row.fetchAll(
                db,
                sql: """
                SELECT l.* FROM labels l
                JOIN transaction_labels tl ON tl.label_id = l.id
                WHERE tl.transaction_id = ?
                ORDER BY l.name
                """,
                arguments: [transaction.id.uuidString]
            )
            let labels = try labelRows.map(Self.label)
            return TransactionListItem(
                id: transaction.id,
                walletName: row["wallet_name"],
                amountMinor: transaction.type == .expense || transaction.type == .transferOut ? -transaction.amountMinor : transaction.amountMinor,
                occurredAt: transaction.occurredAt,
                categoryName: row["category_name"],
                categoryColorHex: row["category_color_hex"],
                categoryIconName: row["category_icon_name"],
                merchant: transaction.merchant ?? Self.fallbackMerchant(for: transaction.type),
                note: transaction.note ?? "",
                kind: transaction.type == .expense ? .expense : (transaction.type == .income ? .income : .transfer),
                source: transaction.source,
                labels: labels,
                dayKey: transaction.localDayKey
            )
        }
    }

    private func balance(atEndOfMonth monthKey: Int, walletID: UUID?, db: Database) throws -> Int64 {
        let monthEnd = Self.endOfMonth(for: monthKey)
        let modifier = """
        CASE
            WHEN t.type IN ('expense', 'transfer_out') THEN -t.amount_minor
            ELSE t.amount_minor
        END
        """

        if let walletID {
            let startingBalance = try Int64.fetchOne(
                db,
                sql: "SELECT COALESCE(starting_balance_minor, 0) FROM wallets WHERE id = ?",
                arguments: [walletID.uuidString]
            ) ?? 0
            let netDelta = try Int64.fetchOne(
                db,
                sql: """
                SELECT COALESCE(SUM(\(modifier)), 0)
                FROM transactions t
                WHERE t.wallet_id = ?
                  AND t.is_deleted = 0
                  AND t.occurred_at <= ?
                """,
                arguments: [walletID.uuidString, monthEnd]
            ) ?? 0
            return startingBalance + netDelta
        }

        let startingBalance = try Int64.fetchOne(
            db,
            sql: "SELECT COALESCE(SUM(starting_balance_minor), 0) FROM wallets WHERE is_archived = 0"
        ) ?? 0
        let netDelta = try Int64.fetchOne(
            db,
            sql: """
            SELECT COALESCE(SUM(\(modifier)), 0)
            FROM transactions t
            WHERE t.is_deleted = 0
              AND t.occurred_at <= ?
            """,
            arguments: [monthEnd]
        ) ?? 0
        return startingBalance + netDelta
    }

    private func syncSearch(_ db: Database, transaction: CashRunwayTransaction) throws {
        try db.execute(sql: "DELETE FROM transaction_search WHERE transaction_id = ?", arguments: [transaction.id.uuidString])
        let walletName = try String.fetchOne(db, sql: "SELECT name FROM wallets WHERE id = ?", arguments: [transaction.walletID.uuidString]) ?? ""
        let labelNames = try String.fetchAll(
            db,
            sql: """
            SELECT l.name FROM labels l
            JOIN transaction_labels tl ON tl.label_id = l.id
            WHERE tl.transaction_id = ?
            """,
            arguments: [transaction.id.uuidString]
        ).joined(separator: " ")
        try db.execute(
            sql: "INSERT INTO transaction_search (transaction_id, merchant, note, wallet_name, labels) VALUES (?, ?, ?, ?, ?)",
            arguments: [transaction.id.uuidString, transaction.merchant ?? "", transaction.note ?? "", walletName, labelNames]
        )
    }

    private func rebuildMonths(_ db: Database, monthKeys: Set<Int>) throws {
        for monthKey in monthKeys {
            try db.execute(sql: "DELETE FROM monthly_wallet_cashflow WHERE month_key = ?", arguments: [monthKey])
            try db.execute(sql: "DELETE FROM monthly_category_spend WHERE month_key = ?", arguments: [monthKey])
            try db.execute(sql: "DELETE FROM budget_progress_snapshot WHERE month_key = ?", arguments: [monthKey])

            let rows = try Row.fetchAll(db, sql: "SELECT * FROM transactions WHERE is_deleted = 0 AND local_month_key = ?", arguments: [monthKey])
            for row in rows {
                let transaction = try Self.transaction(row)
                try mutateAggregate(db, contribution: contribution(for: transaction), multiplier: 1)
            }
        }
        try recomputeBudgetSnapshots(db, monthKeys: monthKeys)
    }

    private func markDirtyRanges(_ db: Database, monthKeys: Set<Int>) throws {
        guard !monthKeys.isEmpty else { return }
        let now = Date()
        for monthKey in monthKeys {
            try db.execute(
                sql: """
                INSERT INTO aggregate_dirty_ranges (id, kind, month_key, status, created_at, updated_at)
                VALUES (?, 'month', ?, 'pending', ?, ?)
                """,
                arguments: [UUID().uuidString, monthKey, now, now]
            )
        }
    }

    private func processPendingAggregateRebuilds(_ db: Database) throws {
        let monthKeys = Set(try Int.fetchAll(
            db,
            sql: "SELECT DISTINCT month_key FROM aggregate_dirty_ranges WHERE kind = 'month' AND status = 'pending' AND month_key IS NOT NULL"
        ))
        guard !monthKeys.isEmpty else { return }
        let startedAt = Date()
        for monthKey in monthKeys {
            try db.execute(
                sql: "UPDATE aggregate_dirty_ranges SET status = 'running', updated_at = ? WHERE kind = 'month' AND month_key = ? AND status = 'pending'",
                arguments: [startedAt, monthKey]
            )
        }
        try rebuildMonths(db, monthKeys: monthKeys)
        let finishedAt = Date()
        for monthKey in monthKeys {
            try db.execute(
                sql: "UPDATE aggregate_dirty_ranges SET status = 'done', updated_at = ? WHERE kind = 'month' AND month_key = ? AND status = 'running'",
                arguments: [finishedAt, monthKey]
            )
        }
    }

    private func rebuildFTS(_ db: Database) throws {
        try db.execute(sql: "DELETE FROM transaction_search")
        let rows = try Row.fetchAll(db, sql: "SELECT * FROM transactions WHERE is_deleted = 0")
        for row in rows {
            try syncSearch(db, transaction: try Self.transaction(row))
        }
    }

    private func refreshRecurringInstances(_ db: Database) throws {
        let calendar = DateKeys.calendar
        let start = calendar.date(byAdding: .day, value: -7, to: .now) ?? .now
        let end = calendar.date(byAdding: .day, value: 60, to: .now) ?? .now
        let templates = try Row.fetchAll(db, sql: "SELECT * FROM recurring_templates WHERE is_active = 1").map(Self.recurringTemplate)
        for template in templates {
            for dueDate in Self.generatedDates(for: template, start: start, end: end) {
                let dayKey = DateKeys.dayKey(for: dueDate)
                try db.execute(
                    sql: """
                    INSERT OR IGNORE INTO recurring_instances (id, template_id, due_date, day_key, status, linked_transaction_id, override_amount_minor, override_category_id, override_note, override_merchant, created_at, updated_at)
                    VALUES (?, ?, ?, ?, ?, NULL, NULL, NULL, NULL, NULL, ?, ?)
                    """,
                    arguments: [UUID().uuidString, template.id.uuidString, dueDate, dayKey, RecurringInstanceStatus.scheduled.rawValue, Date(), Date()]
                )
            }
        }
    }

    public static func generatedDates(for template: RecurringTemplate, start: Date, end: Date) -> [Date] {
        var dates: [Date] = []
        var cursor = max(start, template.startDate)
        let calendar = DateKeys.calendar
        while cursor <= end {
            if let endDate = template.endDate, cursor > endDate { break }
            let match: Bool
            switch template.ruleType {
            case .daily:
                match = calendar.dateComponents([.day], from: template.startDate, to: cursor).day! % template.ruleInterval == 0
            case .weekly:
                match = calendar.dateComponents([.day], from: template.startDate, to: cursor).day! % (7 * template.ruleInterval) == 0
            case .monthly:
                let comps = calendar.dateComponents([.day], from: cursor)
                match = comps.day == template.dayOfMonth
            case .yearly:
                let current = calendar.dateComponents([.month, .day], from: cursor)
                let startComps = calendar.dateComponents([.month, .day], from: template.startDate)
                match = current.month == startComps.month && current.day == (template.dayOfMonth ?? startComps.day)
            }
            if match {
                dates.append(cursor)
            }
            cursor = calendar.date(byAdding: .day, value: 1, to: cursor) ?? cursor.addingTimeInterval(86_400)
        }
        return dates
    }

    private static func fallbackMerchant(for type: TransactionKind) -> String {
        switch type {
        case .expense: "Expense"
        case .income: "Income"
        case .transferOut: "Transfer"
        case .transferIn: "Transfer In"
        }
    }

    private static func wallet(_ row: Row) throws -> Wallet {
        Wallet(
            id: UUID(uuidString: row["id"])!,
            name: row["name"],
            kind: WalletKind(rawValue: row["kind"]) ?? .other,
            colorHex: row["color_hex"],
            iconName: row["icon_name"],
            startingBalanceMinor: row["starting_balance_minor"],
            currentBalanceMinor: row["current_balance_minor"],
            isArchived: row["is_archived"],
            sortOrder: row["sort_order"],
            createdAt: row["created_at"],
            updatedAt: row["updated_at"]
        )
    }

    private static func category(_ row: Row) throws -> Category {
        try category(prefixed: "", row: row)
    }

    private static func monthWindow(endingAt monthKey: Int, count: Int) -> [Int] {
        let start = DateKeys.startOfMonth(for: monthKey)
        return (0..<count).compactMap { offset in
            DateKeys.calendar.date(byAdding: .month, value: offset - (count - 1), to: start)
        }.map(DateKeys.monthKey(for:))
    }

    private static func yearWindow(endingAt year: Int, count: Int) -> [Int] {
        (0..<count).map { year + $0 - (count - 1) }
    }

    private static func endOfMonth(for monthKey: Int) -> Date {
        let start = DateKeys.startOfMonth(for: monthKey)
        let nextMonth = DateKeys.calendar.date(byAdding: .month, value: 1, to: start) ?? start
        return DateKeys.calendar.date(byAdding: .second, value: -1, to: nextMonth) ?? nextMonth
    }

    private static func category(prefixed prefix: String, row: Row) throws -> Category {
        Category(
            id: UUID(uuidString: row["\(prefix)id"])!,
            name: row["\(prefix)name"],
            kind: CategoryKind(rawValue: row["\(prefix)kind"]) ?? .expense,
            iconName: row["\(prefix)icon_name"],
            colorHex: row["\(prefix)color_hex"],
            parentID: (row["\(prefix)parent_id"] as String?).flatMap(UUID.init(uuidString:)),
            isSystem: row["\(prefix)is_system"],
            isArchived: row["\(prefix)is_archived"],
            sortOrder: row["\(prefix)sort_order"],
            createdAt: row["\(prefix)created_at"],
            updatedAt: row["\(prefix)updated_at"]
        )
    }

    private static func label(_ row: Row) throws -> Label {
        Label(
            id: UUID(uuidString: row["id"])!,
            name: row["name"],
            colorHex: row["color_hex"],
            createdAt: row["created_at"],
            updatedAt: row["updated_at"]
        )
    }

    private static func transaction(_ row: Row) throws -> CashRunwayTransaction {
        CashRunwayTransaction(
            id: UUID(uuidString: row["id"])!,
            walletID: UUID(uuidString: row["wallet_id"])!,
            type: TransactionKind(rawValue: row["type"]) ?? .expense,
            linkedTransferID: (row["linked_transfer_id"] as String?).flatMap(UUID.init(uuidString:)),
            amountMinor: row["amount_minor"],
            occurredAt: row["occurred_at"],
            localDayKey: row["local_day_key"],
            localMonthKey: row["local_month_key"],
            categoryID: (row["category_id"] as String?).flatMap(UUID.init(uuidString:)),
            merchant: row["merchant"],
            note: row["note"],
            isDeleted: row["is_deleted"],
            source: TransactionSource(rawValue: row["source"]) ?? .manual,
            recurringTemplateID: (row["recurring_template_id"] as String?).flatMap(UUID.init(uuidString:)),
            recurringInstanceID: (row["recurring_instance_id"] as String?).flatMap(UUID.init(uuidString:)),
            createdAt: row["created_at"],
            updatedAt: row["updated_at"]
        )
    }

    private static func budget(_ row: Row) throws -> Budget {
        Budget(
            id: UUID(uuidString: row["id"])!,
            categoryID: UUID(uuidString: row["category_id"])!,
            monthKey: row["month_key"],
            limitMinor: row["limit_minor"],
            isArchived: row["is_archived"],
            createdAt: row["created_at"],
            updatedAt: row["updated_at"]
        )
    }

    private static func recurringTemplate(_ row: Row) throws -> RecurringTemplate {
        RecurringTemplate(
            id: UUID(uuidString: row["id"])!,
            kind: RecurringTemplateKind(rawValue: row["kind"]) ?? .expense,
            walletID: UUID(uuidString: row["wallet_id"])!,
            counterpartyWalletID: (row["counterparty_wallet_id"] as String?).flatMap(UUID.init(uuidString:)),
            amountMinor: row["amount_minor"],
            categoryID: (row["category_id"] as String?).flatMap(UUID.init(uuidString:)),
            merchant: row["merchant"],
            note: row["note"],
            ruleType: RecurrenceRuleType(rawValue: row["rule_type"]) ?? .monthly,
            ruleInterval: row["rule_interval"],
            dayOfMonth: row["day_of_month"],
            weekday: row["weekday"],
            startDate: row["start_date"],
            endDate: row["end_date"],
            isActive: row["is_active"],
            createdAt: row["created_at"],
            updatedAt: row["updated_at"]
        )
    }

    private static func recurringInstance(_ row: Row) throws -> RecurringInstance {
        RecurringInstance(
            id: UUID(uuidString: row["id"])!,
            templateID: UUID(uuidString: row["template_id"])!,
            dueDate: row["due_date"],
            dayKey: row["day_key"],
            status: RecurringInstanceStatus(rawValue: row["status"]) ?? .scheduled,
            linkedTransactionID: (row["linked_transaction_id"] as String?).flatMap(UUID.init(uuidString:)),
            overrideAmountMinor: row["override_amount_minor"],
            overrideCategoryID: (row["override_category_id"] as String?).flatMap(UUID.init(uuidString:)),
            overrideNote: row["override_note"],
            overrideMerchant: row["override_merchant"],
            createdAt: row["created_at"],
            updatedAt: row["updated_at"]
        )
    }
}
