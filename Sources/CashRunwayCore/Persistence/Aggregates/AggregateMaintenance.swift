import Foundation
import GRDB

struct AggregateContribution {
    let walletID: UUID
    let monthKey: Int
    let dayKey: Int
    let type: TransactionKind
    let amountMinor: Int64
    let categoryID: UUID?
    let labelIDs: [UUID]
}

struct CategorySpendDelta {
    let monthKey: Int
    let walletID: UUID
    let expenseMinor: Int64
    let incomeMinor: Int64
    let transactionCount: Int
}

extension CashRunwayRepository {
    func contribution(for transaction: CashRunwayTransaction, labelIDs: [UUID] = []) -> AggregateContribution {
        AggregateContribution(
            walletID: transaction.walletID,
            monthKey: transaction.localMonthKey,
            dayKey: transaction.localDayKey,
            type: transaction.type,
            amountMinor: transaction.amountMinor,
            categoryID: transaction.categoryID,
            labelIDs: labelIDs
        )
    }

    func applyContribution(_ db: Database, old: AggregateContribution?, new: AggregateContribution?) throws {
        if let old {
            try mutateAggregate(db, contribution: old, multiplier: -1)
        }
        if let new {
            try mutateAggregate(db, contribution: new, multiplier: 1)
        }
        let impactedMonthKeys = Set([old?.monthKey, new?.monthKey].compactMap { $0 })
        try recomputeBudgetSnapshots(db, monthKeys: impactedMonthKeys)
    }

    static func categorySpendDeltas(_ db: Database, categoryID: UUID) throws -> [CategorySpendDelta] {
        let rows = try Row.fetchAll(
            db,
            sql: """
            SELECT local_month_key, wallet_id,
                   COALESCE(SUM(CASE WHEN type = 'expense' THEN amount_minor ELSE 0 END), 0) AS expense_minor,
                   COALESCE(SUM(CASE WHEN type = 'income' THEN amount_minor ELSE 0 END), 0) AS income_minor,
                   COUNT(*) AS txn_count
            FROM transactions
            WHERE is_deleted = 0 AND type IN ('expense', 'income') AND category_id = ?
            GROUP BY local_month_key, wallet_id
            """,
            arguments: [categoryID.uuidString]
        )
        return rows.map {
            CategorySpendDelta(
                monthKey: $0["local_month_key"],
                walletID: UUID(uuidString: $0["wallet_id"]) ?? UUID(),
                expenseMinor: $0["expense_minor"],
                incomeMinor: $0["income_minor"],
                transactionCount: $0["txn_count"]
            )
        }
    }

    func applyCategoryMergeDeltas(_ db: Database, oldCategoryID: UUID, newCategoryID: UUID, deltas: [CategorySpendDelta]) throws {
        guard !deltas.isEmpty else { return }
        let now = Date()
        let hasWalletScope = try columnExists(db, table: "monthly_category_spend", column: "wallet_id")
        guard hasWalletScope else {
            // Pre-Phase 4 schema: only expense_minor exists. Recompute aggregates for affected months.
            let monthKeys = Set(deltas.map(\.monthKey))
            try rebuildMonths(db, monthKeys: monthKeys)
            return
        }
        for delta in deltas {
            if delta.expenseMinor > 0 {
                try db.execute(
                    sql: """
                    UPDATE monthly_category_spend
                    SET expense_minor = expense_minor - ?, txn_count = txn_count - ?, updated_at = ?
                    WHERE category_id = ? AND month_key = ? AND wallet_id = ? AND kind = 'expense'
                    """,
                    arguments: [delta.expenseMinor, delta.transactionCount, now, oldCategoryID.uuidString, delta.monthKey, delta.walletID.uuidString]
                )
                try db.execute(
                    sql: "DELETE FROM monthly_category_spend WHERE category_id = ? AND month_key = ? AND wallet_id = ? AND kind = 'expense' AND expense_minor = 0 AND txn_count <= 0",
                    arguments: [oldCategoryID.uuidString, delta.monthKey, delta.walletID.uuidString]
                )
                try db.execute(
                    sql: """
                    INSERT INTO monthly_category_spend (category_id, month_key, wallet_id, kind, expense_minor, income_minor, txn_count, updated_at)
                    VALUES (?, ?, ?, 'expense', ?, 0, ?, ?)
                    ON CONFLICT(category_id, month_key, wallet_id, kind) DO UPDATE SET
                        expense_minor = expense_minor + excluded.expense_minor,
                        txn_count = txn_count + excluded.txn_count,
                        updated_at = excluded.updated_at
                    """,
                    arguments: [newCategoryID.uuidString, delta.monthKey, delta.walletID.uuidString, delta.expenseMinor, delta.transactionCount, now]
                )
            }
            if delta.incomeMinor > 0 {
                try db.execute(
                    sql: """
                    UPDATE monthly_category_spend
                    SET income_minor = income_minor - ?, txn_count = txn_count - ?, updated_at = ?
                    WHERE category_id = ? AND month_key = ? AND wallet_id = ? AND kind = 'income'
                    """,
                    arguments: [delta.incomeMinor, delta.transactionCount, now, oldCategoryID.uuidString, delta.monthKey, delta.walletID.uuidString]
                )
                try db.execute(
                    sql: "DELETE FROM monthly_category_spend WHERE category_id = ? AND month_key = ? AND wallet_id = ? AND kind = 'income' AND income_minor = 0 AND txn_count <= 0",
                    arguments: [oldCategoryID.uuidString, delta.monthKey, delta.walletID.uuidString]
                )
                try db.execute(
                    sql: """
                    INSERT INTO monthly_category_spend (category_id, month_key, wallet_id, kind, expense_minor, income_minor, txn_count, updated_at)
                    VALUES (?, ?, ?, 'income', 0, ?, ?, ?)
                    ON CONFLICT(category_id, month_key, wallet_id, kind) DO UPDATE SET
                        income_minor = income_minor + excluded.income_minor,
                        txn_count = txn_count + excluded.txn_count,
                        updated_at = excluded.updated_at
                    """,
                    arguments: [newCategoryID.uuidString, delta.monthKey, delta.walletID.uuidString, delta.incomeMinor, delta.transactionCount, now]
                )
            }
        }
    }

    func mutateAggregate(_ db: Database, contribution: AggregateContribution, multiplier: Int64) throws {
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

        if contribution.type != .transferOut && contribution.type != .transferIn, let categoryID = contribution.categoryID {
            let hasWalletScope = try columnExists(db, table: "monthly_category_spend", column: "wallet_id")
            if hasWalletScope {
                let (column, kind): (String, String) = contribution.type == .income ? ("income_minor", "income") : ("expense_minor", "expense")
                try db.execute(
                    sql: """
                    INSERT INTO monthly_category_spend (category_id, month_key, wallet_id, kind, \(column), txn_count, updated_at)
                    VALUES (?, ?, ?, ?, ?, ?, ?)
                    ON CONFLICT(category_id, month_key, wallet_id, kind) DO UPDATE SET
                        \(column) = \(column) + excluded.\(column),
                        txn_count = txn_count + excluded.txn_count,
                        updated_at = excluded.updated_at
                    """,
                    arguments: [categoryID.uuidString, contribution.monthKey, contribution.walletID.uuidString, kind, amount, multiplier, now]
                )
                try db.execute(
                    sql: "DELETE FROM monthly_category_spend WHERE category_id = ? AND month_key = ? AND wallet_id = ? AND kind = ? AND \(column) = 0 AND txn_count <= 0",
                    arguments: [categoryID.uuidString, contribution.monthKey, contribution.walletID.uuidString, kind]
                )

                if !contribution.labelIDs.isEmpty,
                   try tableExists(db, name: "monthly_label_spend") {
                    let labelKind = contribution.type == .income ? "income" : "expense"
                    for labelID in contribution.labelIDs {
                        try db.execute(
                            sql: """
                            INSERT INTO monthly_label_spend (label_id, month_key, wallet_id, kind, amount_minor, txn_count, updated_at)
                            VALUES (?, ?, ?, ?, ?, ?, ?)
                            ON CONFLICT(label_id, month_key, wallet_id, kind) DO UPDATE SET
                                amount_minor = amount_minor + excluded.amount_minor,
                                txn_count = txn_count + excluded.txn_count,
                                updated_at = excluded.updated_at
                            """,
                            arguments: [labelID.uuidString, contribution.monthKey, contribution.walletID.uuidString, labelKind, amount, multiplier, now]
                        )
                        try db.execute(
                            sql: "DELETE FROM monthly_label_spend WHERE label_id = ? AND month_key = ? AND wallet_id = ? AND kind = ? AND amount_minor = 0 AND txn_count <= 0",
                            arguments: [labelID.uuidString, contribution.monthKey, contribution.walletID.uuidString, labelKind]
                        )
                    }
                }
            } else {
                // Pre-Phase 4 schema: only expense_minor is tracked.
                if contribution.type == .expense {
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
            }
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

    func recomputeBudgetSnapshots(_ db: Database, monthKeys: Set<Int>) throws {
        guard !monthKeys.isEmpty else { return }
        let now = Date()
        let hasWalletScope = try columnExists(db, table: "monthly_category_spend", column: "wallet_id")
        for monthKey in monthKeys {
            let spendSQL = hasWalletScope
                ? """
                SELECT b.id, b.limit_minor, COALESCE(SUM(m.expense_minor), 0) AS spent_minor
                FROM budgets b
                LEFT JOIN monthly_category_spend m ON m.category_id = b.category_id AND m.month_key = b.month_key AND m.kind = 'expense'
                WHERE b.month_key = ? AND b.is_archived = 0
                GROUP BY b.id
                """
                : """
                SELECT b.id, b.limit_minor, COALESCE(m.expense_minor, 0) AS spent_minor
                FROM budgets b
                LEFT JOIN monthly_category_spend m ON m.category_id = b.category_id AND m.month_key = b.month_key
                WHERE b.month_key = ? AND b.is_archived = 0
                """
            let rows = try Row.fetchAll(
                db,
                sql: spendSQL,
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

    // swiftlint:disable:next cyclomatic_complexity
    func listTransactions(_ db: Database, query: TransactionQuery, limit: Int? = 300) throws -> [TransactionListItem] {
        var conditions = ["t.is_deleted = 0", "t.type != 'transfer_in'"]
        var arguments: [String: any DatabaseValueConvertible] = [:]

        if query.walletID == nil {
            conditions.append(Self.activeWalletScope(nil, column: "w.id").fragment)
        }

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
            conditions.append("t.local_day_key >= :startDayKey")
            arguments["startDayKey"] = DateKeys.dayKey(for: startDate)
        }
        if let endDate = query.endDate {
            conditions.append("t.local_day_key <= :endDayKey")
            arguments["endDayKey"] = DateKeys.dayKey(for: endDate)
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
        SELECT t.*, w.name AS wallet_name, c.id AS category_id, c.name AS category_name, c.color_hex AS category_color_hex, c.icon_name AS category_icon_name
        FROM transactions t
        JOIN wallets w ON w.id = t.wallet_id
        LEFT JOIN categories c ON c.id = t.category_id
        WHERE \(conditions.joined(separator: " AND "))
        ORDER BY t.occurred_at DESC, t.created_at DESC
        \(limit.map { "LIMIT \($0)" } ?? "")
        \(query.offset > 0 ? "OFFSET \(query.offset)" : "")
        """

        let rows = try Row.fetchAll(db, sql: sql, arguments: StatementArguments(arguments))
        let transactionIDs = rows.compactMap { row -> String? in row["id"] }
        let labelsByTransactionID: [UUID: [Label]] = try {
            if transactionIDs.isEmpty {
                return [:]
            }
            // SQLite default limit is 999 variables per query; chunk to stay safely under.
            let chunkSize = 900
            var dict: [UUID: [Label]] = [:]
            for index in stride(from: 0, to: transactionIDs.count, by: chunkSize) {
                let chunk = Array(transactionIDs[index..<min(index + chunkSize, transactionIDs.count)])
                let inPlaceholders = chunk.enumerated().map { ":txLabel\($0.offset)" }.joined(separator: ", ")
                let labelSQL = """
                SELECT tl.transaction_id, l.* FROM labels l
                JOIN transaction_labels tl ON tl.label_id = l.id
                WHERE tl.transaction_id IN (\(inPlaceholders))
                ORDER BY l.name
                """
                var labelArgs: [String: any DatabaseValueConvertible] = [:]
                for (index, txID) in chunk.enumerated() {
                    labelArgs["txLabel\(index)"] = txID
                }
                let labelRows = try Row.fetchAll(db, sql: labelSQL, arguments: StatementArguments(labelArgs))
                for labelRow in labelRows {
                    if let txID = UUID(uuidString: labelRow["transaction_id"]) {
                        var arr = dict[txID, default: []]
                        arr.append(try Self.label(labelRow))
                        dict[txID] = arr
                    }
                }
            }
            return dict
        }()

        return try rows.map { row in
            let transaction = try Self.transaction(row)
            let labels = labelsByTransactionID[transaction.id] ?? []
            return TransactionListItem(
                id: transaction.id,
                walletName: row["wallet_name"],
                amountMinor: transaction.type == .expense || transaction.type == .transferOut ? -transaction.amountMinor : transaction.amountMinor,
                currencyCode: transaction.currencyCode,
                occurredAt: transaction.occurredAt,
                categoryName: row["category_name"],
                categoryID: row["category_id"],
                categoryColorHex: row["category_color_hex"],
                categoryIconName: row["category_icon_name"],
                merchant: transaction.merchant ?? "",
                note: transaction.note ?? "",
                kind: transaction.type == .expense ? .expense : (transaction.type == .income ? .income : .transfer),
                source: transaction.source,
                labels: labels,
                dayKey: transaction.localDayKey
            )
        }
    }

    func balance(atEndOfMonth monthKey: Int, walletID: UUID?, db: Database) throws -> Int64 {
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

    /// Computes ending balances for multiple months in a single pass using the aggregate table.
    /// This is O(1) per month after the initial query, vs. O(n) per month when summing all transactions.
    func monthEndBalances(for months: [Int], walletID: UUID?, db: Database) throws -> [Int: Int64] {
        guard !months.isEmpty else { return [:] }
        let sortedMonths = Set(months).sorted()
        let latest = sortedMonths.last!
        let scope = Self.activeWalletScope(walletID)

        let startingBalance: Int64
        if let walletID {
            startingBalance = try Int64.fetchOne(
                db,
                sql: "SELECT COALESCE(starting_balance_minor, 0) FROM wallets WHERE id = ?",
                arguments: [walletID.uuidString]
            ) ?? 0
        } else {
            startingBalance = try Int64.fetchOne(
                db,
                sql: "SELECT COALESCE(SUM(starting_balance_minor), 0) FROM wallets WHERE is_archived = 0"
            ) ?? 0
        }

        let rows = try Row.fetchAll(
            db,
            sql: """
            SELECT month_key,
                   COALESCE(SUM(income_minor - expense_minor + transfer_in_minor - transfer_out_minor), 0) AS net_delta
            FROM monthly_wallet_cashflow
            WHERE month_key <= ?
            AND \(scope.fragment)
            GROUP BY month_key
            ORDER BY month_key
            """,
            arguments: StatementArguments([latest] + scope.arguments)
        )

        var cumulative = startingBalance
        var balances: [Int: Int64] = [:]
        var rowIndex = 0
        for month in sortedMonths {
            while rowIndex < rows.count, (rows[rowIndex]["month_key"] as Int) <= month {
                cumulative += rows[rowIndex]["net_delta"] as Int64
                rowIndex += 1
            }
            balances[month] = cumulative
        }
        return balances
    }

    func syncSearch(_ db: Database, transaction: CashRunwayTransaction) throws {
        try db.execute(sql: "DELETE FROM transaction_search WHERE transaction_id = ?", arguments: [transaction.id.uuidString])
        let walletName = try String.fetchOne(db, sql: "SELECT name FROM wallets WHERE id = ?", arguments: [transaction.walletID.uuidString]) ?? ""
        let categoryName = transaction.categoryID.flatMap {
            try? String.fetchOne(db, sql: "SELECT name FROM categories WHERE id = ?", arguments: [$0.uuidString])
        } ?? ""
        let labelNames = try String.fetchAll(
            db,
            sql: """
            SELECT l.name FROM labels l
            JOIN transaction_labels tl ON tl.label_id = l.id
            WHERE tl.transaction_id = ?
            """,
            arguments: [transaction.id.uuidString]
        ).joined(separator: " ")
        let merchantSearchText = MaskedCardIdentifier.privacyPreservingSearchText(for: transaction.merchant ?? "")
        try db.execute(
            sql: "INSERT INTO transaction_search (transaction_id, merchant, note, wallet_name, category_name, labels) VALUES (?, ?, ?, ?, ?, ?)",
            arguments: [transaction.id.uuidString, merchantSearchText, transaction.note ?? "", walletName, categoryName, labelNames]
        )
    }

    func syncSearch(_ db: Database, transactionIDs: [String]) throws {
        guard !transactionIDs.isEmpty else { return }

        let chunkSize = 900
        for index in stride(from: 0, to: transactionIDs.count, by: chunkSize) {
            let chunk = Array(transactionIDs[index..<min(index + chunkSize, transactionIDs.count)])
            let placeholders = chunk.enumerated().map { ":id\($0.offset)" }.joined(separator: ", ")
            var arguments: [String: any DatabaseValueConvertible] = [:]
            for (index, transactionID) in chunk.enumerated() {
                arguments["id\(index)"] = transactionID
            }
            let rows = try Row.fetchAll(
                db,
                sql: "SELECT * FROM transactions WHERE is_deleted = 0 AND id IN (\(placeholders))",
                arguments: StatementArguments(arguments)
            )
            for row in rows {
                try syncSearch(db, transaction: try Self.transaction(row))
            }
        }
    }

    func rebuildMonths(_ db: Database, monthKeys: Set<Int>) throws {
        let allMonths = try Int.fetchAll(
            db,
            sql: "SELECT DISTINCT local_month_key FROM transactions WHERE is_deleted = 0 AND local_month_key IS NOT NULL"
        )
        let monthKeys = monthKeys.union(Set(allMonths))
        guard !monthKeys.isEmpty else { return }
        let now = Date()

        let inPlaceholders = monthKeys.enumerated().map { ":month\($0.offset)" }.joined(separator: ", ")
        var inArgs: [String: any DatabaseValueConvertible] = [:]
        for (index, monthKey) in monthKeys.enumerated() {
            inArgs["month\(index)"] = monthKey
        }

        try db.execute(
            sql: "DELETE FROM monthly_wallet_cashflow WHERE month_key IN (\(inPlaceholders))",
            arguments: StatementArguments(inArgs)
        )
        let hasWalletScope = try columnExists(db, table: "monthly_category_spend", column: "wallet_id")
        try db.execute(
            sql: "DELETE FROM monthly_category_spend WHERE month_key IN (\(inPlaceholders))",
            arguments: StatementArguments(inArgs)
        )
        if try tableExists(db, name: "monthly_label_spend") {
            try db.execute(
                sql: "DELETE FROM monthly_label_spend WHERE month_key IN (\(inPlaceholders))",
                arguments: StatementArguments(inArgs)
            )
        }
        try db.execute(
            sql: "DELETE FROM budget_progress_snapshot WHERE month_key IN (\(inPlaceholders))",
            arguments: StatementArguments(inArgs)
        )

        let sortedMonthKeys = monthKeys.sorted()
        let monthKeyArgs: [any DatabaseValueConvertible] = sortedMonthKeys

        if hasWalletScope {
            try db.execute(
                sql: """
                INSERT INTO monthly_category_spend (category_id, month_key, wallet_id, kind, expense_minor, income_minor, txn_count, updated_at)
                SELECT
                    t.category_id,
                    t.local_month_key,
                    t.wallet_id,
                    CASE t.type WHEN 'income' THEN 'income' ELSE 'expense' END,
                    SUM(CASE WHEN t.type = 'expense' THEN t.amount_minor ELSE 0 END),
                    SUM(CASE WHEN t.type = 'income' THEN t.amount_minor ELSE 0 END),
                    COUNT(t.id),
                    ?
                FROM transactions t
                WHERE t.is_deleted = 0
                  AND t.type IN ('expense', 'income')
                  AND t.category_id IS NOT NULL
                  AND t.local_month_key IN (\(inPlaceholders))
                GROUP BY t.category_id, t.local_month_key, t.wallet_id, CASE t.type WHEN 'income' THEN 'income' ELSE 'expense' END
                """,
                arguments: StatementArguments([now] + monthKeyArgs)
            )

            if try tableExists(db, name: "monthly_label_spend") {
                try db.execute(
                    sql: """
                    INSERT INTO monthly_label_spend (label_id, month_key, wallet_id, kind, amount_minor, txn_count, updated_at)
                    SELECT
                        tl.label_id,
                        t.local_month_key,
                        t.wallet_id,
                        CASE t.type WHEN 'income' THEN 'income' ELSE 'expense' END,
                        SUM(t.amount_minor),
                        COUNT(DISTINCT t.id),
                        ?
                    FROM transaction_labels tl
                    JOIN transactions t ON t.id = tl.transaction_id
                    WHERE t.is_deleted = 0
                      AND t.type IN ('expense', 'income')
                      AND t.local_month_key IN (\(inPlaceholders))
                    GROUP BY tl.label_id, t.local_month_key, t.wallet_id, CASE t.type WHEN 'income' THEN 'income' ELSE 'expense' END
                    """,
                    arguments: StatementArguments([now] + monthKeyArgs)
                )
            }
        } else {
            // Pre-Phase 4 schema: only expense_minor is tracked per category/month.
            try db.execute(
                sql: """
                INSERT INTO monthly_category_spend (category_id, month_key, expense_minor, txn_count, updated_at)
                SELECT
                    t.category_id,
                    t.local_month_key,
                    SUM(t.amount_minor),
                    COUNT(t.id),
                    ?
                FROM transactions t
                WHERE t.is_deleted = 0
                  AND t.type = 'expense'
                  AND t.category_id IS NOT NULL
                  AND t.local_month_key IN (\(inPlaceholders))
                GROUP BY t.category_id, t.local_month_key
                """,
                arguments: StatementArguments([now] + monthKeyArgs)
            )
        }

        try db.execute(
            sql: """
            INSERT INTO monthly_wallet_cashflow (wallet_id, month_key, income_minor, expense_minor, transfer_in_minor, transfer_out_minor, txn_count, updated_at)
            SELECT
                t.wallet_id,
                t.local_month_key,
                SUM(CASE WHEN t.type = 'income' THEN t.amount_minor ELSE 0 END),
                SUM(CASE WHEN t.type = 'expense' THEN t.amount_minor ELSE 0 END),
                SUM(CASE WHEN t.type = 'transfer_in' THEN t.amount_minor ELSE 0 END),
                SUM(CASE WHEN t.type = 'transfer_out' THEN t.amount_minor ELSE 0 END),
                COUNT(t.id),
                ?
            FROM transactions t
            WHERE t.is_deleted = 0
              AND t.type != 'transfer_in'
              AND t.local_month_key IN (\(inPlaceholders))
            GROUP BY t.wallet_id, t.local_month_key
            """,
            arguments: StatementArguments([now] + monthKeyArgs)
        )

        try recomputeWalletBalances(db)
        try recomputeBudgetSnapshots(db, monthKeys: monthKeys)
    }

    func recomputeWalletBalances(_ db: Database) throws {
        let now = Date()
        try db.execute(
            sql: """
            UPDATE wallets
            SET current_balance_minor = starting_balance_minor + (
                SELECT COALESCE(SUM(
                    CASE t.type
                        WHEN 'expense' THEN -t.amount_minor
                        WHEN 'transfer_out' THEN -t.amount_minor
                        WHEN 'income' THEN t.amount_minor
                        WHEN 'transfer_in' THEN t.amount_minor
                        ELSE 0
                    END
                ), 0)
                FROM transactions t
                WHERE t.wallet_id = wallets.id
                  AND t.is_deleted = 0
            ),
            updated_at = ?
            """,
            arguments: [now]
        )
    }

    func markDirtyRanges(_ db: Database, monthKeys: Set<Int>) throws {
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

    func processPendingAggregateRebuilds(_ db: Database) throws {
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
        try db.execute(sql: "DELETE FROM aggregate_dirty_ranges WHERE kind = 'month' AND status = 'done'")
    }

    func purgeExpiredRawJSON(_ db: Database) throws {
        try db.execute(
            sql: """
            UPDATE bank_transaction_imports
            SET raw_json = NULL
            WHERE raw_json_expires_at IS NOT NULL
              AND raw_json_expires_at <= datetime('now')
              AND raw_json IS NOT NULL
            """
        )
    }

    func rebuildFTS(_ db: Database, chunkSize: Int = 1000) throws {
        try db.execute(sql: "DELETE FROM transaction_search")
        let total = try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM transactions WHERE is_deleted = 0") ?? 0
        guard total > 0 else { return }
        var lastID: String? = nil
        var processed = 0
        while processed < total {
            let rows = try Row.fetchAll(
                db,
                sql: """
                SELECT * FROM transactions
                WHERE is_deleted = 0
                  AND (? IS NULL OR id > ?)
                ORDER BY id
                LIMIT ?
                """,
                arguments: [lastID, lastID, chunkSize]
            )
            guard !rows.isEmpty else { break }
            for row in rows {
                try syncSearch(db, transaction: try Self.transaction(row))
                lastID = row["id"]
                processed += 1
            }
        }
    }
}
