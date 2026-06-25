import Foundation

public enum AppLanguagePreference: String, CaseIterable, Identifiable {
    case system
    case english = "en"
    case ukrainian = "uk"

    public static let storageKey = "cashRunway.languagePreference"

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .system: L10n.string("System")
        case .english: L10n.string("English")
        case .ukrainian: L10n.string("Ukrainian")
        }
    }

    public var resolvedLanguageCode: String {
        switch self {
        case .system:
            let preferred = Locale.preferredLanguages.first?.lowercased() ?? "en"
            return preferred.hasPrefix("uk") ? "uk" : "en"
        case .english:
            return "en"
        case .ukrainian:
            return "uk"
        }
    }

    public var locale: Locale {
        Locale(identifier: resolvedLanguageCode)
    }

    public static func value(for rawValue: String) -> AppLanguagePreference {
        AppLanguagePreference(rawValue: rawValue) ?? .system
    }
}

public enum L10n {
    public static var languagePreference: AppLanguagePreference {
        AppLanguagePreference.value(for: UserDefaults.standard.string(forKey: AppLanguagePreference.storageKey) ?? AppLanguagePreference.system.rawValue)
    }

    public static var locale: Locale {
        languagePreference.locale
    }

    public static var languageCode: String {
        languagePreference.resolvedLanguageCode
    }

    public static func string(_ key: String) -> String {
        if let path = Bundle.main.path(forResource: languageCode, ofType: "lproj"),
           let localizedBundle = Bundle(path: path) {
            return localizedBundle.localizedString(forKey: key, value: key, table: nil)
        }
        return Bundle.main.localizedString(forKey: key, value: key, table: nil)
    }

    public static func string(_ key: String, _ arguments: CVarArg...) -> String {
        String(format: string(key), locale: locale, arguments: arguments)
    }

    public static func walletCount(_ count: Int) -> String {
        plural(count, englishOne: "%d wallet", englishOther: "%d wallets", ukOne: "%d гаманець", ukFew: "%d гаманці", ukMany: "%d гаманців")
    }

    public static func labelCount(_ count: Int) -> String {
        plural(count, englishOne: "%d label", englishOther: "%d labels", ukOne: "%d мітка", ukFew: "%d мітки", ukMany: "%d міток")
    }

    public static func templateCount(_ count: Int) -> String {
        plural(count, englishOne: "%d template", englishOther: "%d templates", ukOne: "%d шаблон", ukFew: "%d шаблони", ukMany: "%d шаблонів")
    }

    public static func transactionCount(_ count: Int) -> String {
        plural(count, englishOne: "%d transaction", englishOther: "%d transactions", ukOne: "%d транзакція", ukFew: "%d транзакції", ukMany: "%d транзакцій")
    }

    public static func deleteTransactionsButtonTitle(_ count: Int) -> String {
        plural(count, englishOne: "Delete %d transaction", englishOther: "Delete %d transactions", ukOne: "Видалити %d транзакцію", ukFew: "Видалити %d транзакції", ukMany: "Видалити %d транзакцій")
    }

    public static func cardCount(_ count: Int) -> String {
        plural(count, englishOne: "%d card", englishOther: "%d cards", ukOne: "%d картка", ukFew: "%d картки", ukMany: "%d карток")
    }

    public static func rowCount(_ count: Int) -> String {
        plural(count, englishOne: "%d row", englishOther: "%d rows", ukOne: "%d рядок", ukFew: "%d рядки", ukMany: "%d рядків")
    }

    public static func walletKind(_ kind: WalletKind) -> String {
        switch kind {
        case .cash: string("walletKind.cash")
        case .card: string("walletKind.card")
        case .account: string("walletKind.account")
        case .other: string("walletKind.other")
        }
    }

    public static func transactionKind(_ kind: TransactionDraft.Kind) -> String {
        switch kind {
        case .expense: string("Expense")
        case .income: string("Income")
        case .transfer: string("Transfer")
        }
    }

    public static func timelinePeriod(_ period: TimelinePeriod) -> String {
        switch period {
        case .month: string("Month")
        case .year: string("Year")
        }
    }

    static func plural(
        _ count: Int,
        englishOne: String,
        englishOther: String,
        ukOne: String,
        ukFew: String,
        ukMany: String
    ) -> String {
        let format: String
        if languageCode == "uk" {
            let mod10 = count % 10
            let mod100 = count % 100
            if mod10 == 1 && mod100 != 11 {
                format = ukOne
            } else if (2...4).contains(mod10) && !(12...14).contains(mod100) {
                format = ukFew
            } else {
                format = ukMany
            }
        } else {
            format = count == 1 ? englishOne : englishOther
        }
        return String(format: format, locale: locale, count)
    }
}

public enum BuiltInCategoryDisplayName {
    private static let keysByID: [UUID: String] = [
        UUID(uuidString: "11111111-1111-1111-1111-111111111111")!: "category.groceries",
        UUID(uuidString: "11111111-1111-1111-1111-111111111112")!: "category.restaurants",
        UUID(uuidString: "11111111-1111-1111-1111-111111111113")!: "category.transport",
        UUID(uuidString: "11111111-1111-1111-1111-111111111114")!: "category.housing",
        UUID(uuidString: "11111111-1111-1111-1111-111111111115")!: "category.utilities",
        UUID(uuidString: "11111111-1111-1111-1111-111111111116")!: "category.health",
        UUID(uuidString: "11111111-1111-1111-1111-111111111117")!: "category.shopping",
        UUID(uuidString: "11111111-1111-1111-1111-111111111118")!: "category.entertainment",
        UUID(uuidString: "11111111-1111-1111-1111-111111111119")!: "category.education",
        UUID(uuidString: "11111111-1111-1111-1111-111111111120")!: "category.travel",
        UUID(uuidString: "11111111-1111-1111-1111-111111111121")!: "category.gifts",
        UUID(uuidString: "11111111-1111-1111-1111-111111111122")!: "category.otherExpense",
        UUID(uuidString: "22222222-2222-2222-2222-222222222111")!: "category.salary",
        UUID(uuidString: "22222222-2222-2222-2222-222222222112")!: "category.bonus",
        UUID(uuidString: "22222222-2222-2222-2222-222222222113")!: "category.giftIncome",
        UUID(uuidString: "22222222-2222-2222-2222-222222222114")!: "category.refund",
        UUID(uuidString: "22222222-2222-2222-2222-222222222115")!: "category.otherIncome",
    ]

    public static func name(id: UUID, fallback: String) -> String {
        guard let key = keysByID[id] else { return fallback }
        return L10n.string(key)
    }

    public static func name(_ category: Category) -> String {
        name(id: category.id, fallback: category.name)
    }

    public static func name(_ category: OverviewCategoryRow) -> String {
        name(id: category.id, fallback: category.name)
    }
}
