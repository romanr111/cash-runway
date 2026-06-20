import Foundation

/// Maps Ukrainian/Russian bank-provided category names to canonical Cash Runway
/// category names defined in `SeedCategories`.
///
/// Matching is intentionally conservative: keywords are relatively long and are
/// checked as substrings only after normalization, so accidental matches are rare.
public enum BankCategoryNameMapping {
    public static func categoryName(for rawName: String, kind: TransactionDraft.Kind) -> String? {
        let normalized = normalizedText(rawName)
        let words = Set(normalized.components(separatedBy: " "))
        let rules = kind == .income ? incomeRules : expenseRules
        for rule in rules {
            if rule.keywords.contains(where: { matches(keyword: normalizedText($0), in: normalized, words: words) }) {
                return rule.categoryName
            }
        }
        return nil
    }

    private static func matches(keyword: String, in normalized: String, words: Set<String>) -> Bool {
        if keyword.contains(" ") {
            return normalized.contains(keyword)
        }
        if keyword.count <= 3 {
            return words.contains(keyword)
        }
        return words.contains { $0 == keyword || $0.hasPrefix(keyword) }
    }

    private static func normalizedText(_ input: String) -> String {
        input
            .precomposedStringWithCanonicalMapping
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "uk_UA"))
            .lowercased()
            .replacingOccurrences(of: "'", with: " ")
            .replacingOccurrences(of: "\u{2019}", with: " ")
            .replacingOccurrences(of: "&", with: " ")
            .replacingOccurrences(of: "-", with: " ")
            .replacingOccurrences(of: "_", with: " ")
            .replacingOccurrences(of: "/", with: " ")
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }

    private struct Rule {
        let keywords: [String]
        let categoryName: String
    }

    // MARK: - Expense

    private static let expenseRules: [Rule] = [
        Rule(
            keywords: ["ресторан", "кафе", "бар", "їдальня", "фастфуд", "столовая", "фаст-фуд"],
            categoryName: "Restaurants"
        ),
        Rule(
            keywords: [
                "супермаркет", "продукти", "продуктовий", "гастроном", "бакалія",
                "супермаркеты", "продукты", "продуктовый", "бакалея"
            ],
            categoryName: "Groceries"
        ),
        Rule(
            keywords: ["азс", "паливо", "бензин", "заправка", "топливо", "бензозаправка"],
            categoryName: "Transport"
        ),
        Rule(
            keywords: ["таксі", "такси", "taxi", "uber", "bolt"],
            categoryName: "Transport"
        ),
        Rule(
            keywords: [
                "авто", "автомобіль", "автомобиль", "автозапчастини", "автозапчасти",
                "автосервіс", "автосервис", "автомийка", "шиномонтаж"
            ],
            categoryName: "Transport"
        ),
        Rule(
            keywords: [
                "квиток", "квитки", "поїзд", "залізниця", "авіалінії", "авіаквиток",
                "готель", "відпочинок", "турагентство", "билет", "поезд", "железная дорога",
                "авиалинии", "отель", "туризм", "турагентство"
            ],
            categoryName: "Travel"
        ),
        Rule(
            keywords: ["квіти", "букет", "подарунок", "цветы", "подарок"],
            categoryName: "Gifts"
        ),
        Rule(
            keywords: [
                "одяг", "взуття", "краса", "косметика", "парфум", "цифрові товари", "електроніка",
                "комп'ютер", "техніка", "маркетплейс", "інтернет магазин", "одежда", "обувь",
                "косметика", "парфюм", "электроника", "компьютер", "техника", "маркетплейс",
                "интернет магазин"
            ],
            categoryName: "Shopping"
        ),
        Rule(
            keywords: [
                "дім", "ремонт", "будівництво", "меблі", "нерухомість", "комунальні",
                "дом", "строительство", "мебель", "недвижимость"
            ],
            categoryName: "Housing"
        ),
        Rule(
            keywords: [
                "медичні", "лікар", "аптек", "здоров'я", "стоматолог", "лікарня",
                "медицинские", "врач", "аптек", "здоровье", "стоматолог", "больница"
            ],
            categoryName: "Health"
        ),
        Rule(
            keywords: [
                "спорт", "фітнес", "кінотеатр", "театр", "концерт", "розваги",
                "фитнес", "кино", "концерт", "развлечения"
            ],
            categoryName: "Entertainment"
        ),
        Rule(
            keywords: [
                "фінанси", "банк", "банки", "кредит", "кредити", "комісія",
                "финансы", "банк", "банки", "кредит", "кредиты", "комиссия"
            ],
            categoryName: "Utilities"
        ),
        Rule(
            keywords: [
                "освіта", "курси", "навчання", "школа", "університет",
                "образование", "курсы", "обучение", "школа", "университет"
            ],
            categoryName: "Education"
        ),
        Rule(
            keywords: [
                "послуги", "страхування",
                "услуги", "страхование"
            ],
            categoryName: "Other Expense"
        )
    ]

    // MARK: - Income

    private static let incomeRules: [Rule] = [
        Rule(
            keywords: [
                "зарахування", "переказ", "поповнення", "відсотки", "кешбек",
                "зачисление", "перевод", "пополнение", "проценты", "кешбек"
            ],
            categoryName: "Other Income"
        ),
        Rule(
            keywords: ["зарплат", "заробіт", "зарплат", "заработ"],
            categoryName: "Salary"
        ),
        Rule(
            keywords: ["прем", "бонус"],
            categoryName: "Bonus"
        ),
        Rule(
            keywords: ["подарунок", "повернення", "подарок", "возврат"],
            categoryName: "Refund"
        )
    ]
}
