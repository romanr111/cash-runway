import Foundation
import GRDB

extension CashRunwayRepository {
    func refreshRecurringInstances(_ db: Database) throws {
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

    public static func generatedDates(
        for template: RecurringTemplate,
        start: Date,
        end: Date,
        calendar: Calendar = DateKeys.calendar
    ) -> [Date] {
        var dates: [Date] = []
        var cursor = max(start, template.startDate)
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
                let monthsFromStart = calendar.dateComponents([.month], from: template.startDate, to: cursor).month ?? 0
                match = comps.day == template.dayOfMonth && monthsFromStart % template.ruleInterval == 0
            case .yearly:
                let current = calendar.dateComponents([.month, .day], from: cursor)
                let startComps = calendar.dateComponents([.month, .day], from: template.startDate)
                let yearsFromStart = calendar.dateComponents([.year], from: template.startDate, to: cursor).year ?? 0
                match = current.month == startComps.month && current.day == (template.dayOfMonth ?? startComps.day) && yearsFromStart % template.ruleInterval == 0
            }
            if match {
                dates.append(cursor)
            }
            cursor = calendar.date(byAdding: .day, value: 1, to: cursor) ?? cursor.addingTimeInterval(86_400)
        }
        return dates
    }

    static func recurringTemplate(_ row: Row) throws -> RecurringTemplate {
        RecurringTemplate(
            id: UUID(uuidString: row["id"])!,
            kind: RecurringTemplateKind(rawValue: row["kind"]) ?? .expense,
            walletID: UUID(uuidString: row["wallet_id"])!,
            counterpartyWalletID: (row["counterparty_wallet_id"] as String?).flatMap(UUID.init(uuidString:)),
            amountMinor: row["amount_minor"],
            currencyCode: CurrencyCode(rawValue: (row["currency_code"] as String?) ?? "UAH"),
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
}
