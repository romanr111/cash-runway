import Foundation
import Testing
@testable import CashRunwayCore

@Suite(.serialized)
struct LocalizationCoreTests {

    // MARK: - AppLanguagePreference

    @Test func appLanguagePreferenceValueForReturnsCorrectEnum() {
        #expect(AppLanguagePreference.value(for: "system") == .system)
        #expect(AppLanguagePreference.value(for: "en") == .english)
        #expect(AppLanguagePreference.value(for: "uk") == .ukrainian)
    }

    @Test func appLanguagePreferenceValueForReturnsSystemForUnknown() {
        #expect(AppLanguagePreference.value(for: "fr") == .system)
        #expect(AppLanguagePreference.value(for: "") == .system)
        #expect(AppLanguagePreference.value(for: "invalid") == .system)
    }

    @Test func appLanguagePreferenceResolvedLanguageCodeEnglish() {
        #expect(AppLanguagePreference.english.resolvedLanguageCode == "en")
    }

    @Test func appLanguagePreferenceResolvedLanguageCodeUkrainian() {
        #expect(AppLanguagePreference.ukrainian.resolvedLanguageCode == "uk")
    }

    @Test func appLanguagePreferenceSystemResolvesToDeviceLanguage() {
        let code = AppLanguagePreference.system.resolvedLanguageCode
        if Locale.preferredLanguages.first?.lowercased().hasPrefix("uk") == true {
            #expect(code == "uk")
        } else {
            #expect(code == "en")
        }
    }

    @Test func appLanguagePreferenceLocaleMatchesCode() {
        #expect(AppLanguagePreference.english.locale.identifier == "en")
        #expect(AppLanguagePreference.ukrainian.locale.identifier == "uk")
    }

    // MARK: - L10n.plural() English forms

    @Test func pluralEnglishOne() {
        let result = L10n.plural(1, englishOne: "%d wallet", englishOther: "%d wallets", ukOne: "", ukFew: "", ukMany: "")
        #expect(result == "1 wallet")
    }

    @Test func pluralEnglishOther() {
        let result = L10n.plural(2, englishOne: "%d wallet", englishOther: "%d wallets", ukOne: "", ukFew: "", ukMany: "")
        #expect(result == "2 wallets")
    }

    @Test func pluralEnglishZero() {
        let result = L10n.plural(0, englishOne: "%d wallet", englishOther: "%d wallets", ukOne: "", ukFew: "", ukMany: "")
        #expect(result == "0 wallets")
    }

    // MARK: - L10n.plural() Ukrainian forms

    @Test func pluralUkrainianOne() {
        let key = AppLanguagePreference.storageKey
        let prior = UserDefaults.standard.string(forKey: key)
        UserDefaults.standard.set("uk", forKey: key)
        defer {
            if let prior {
                UserDefaults.standard.set(prior, forKey: key)
            } else {
                UserDefaults.standard.removeObject(forKey: key)
            }
        }
        #expect(L10n.plural(1, englishOne: "", englishOther: "", ukOne: "%d гаманець", ukFew: "", ukMany: "") == "1 гаманець")
        #expect(L10n.plural(21, englishOne: "", englishOther: "", ukOne: "%d гаманець", ukFew: "", ukMany: "") == "21 гаманець")
    }

    @Test func pluralUkrainianFew() {
        let key = AppLanguagePreference.storageKey
        let prior = UserDefaults.standard.string(forKey: key)
        UserDefaults.standard.set("uk", forKey: key)
        defer {
            if let prior {
                UserDefaults.standard.set(prior, forKey: key)
            } else {
                UserDefaults.standard.removeObject(forKey: key)
            }
        }
        #expect(L10n.plural(2, englishOne: "", englishOther: "", ukOne: "", ukFew: "%d гаманці", ukMany: "") == "2 гаманці")
        #expect(L10n.plural(3, englishOne: "", englishOther: "", ukOne: "", ukFew: "%d гаманці", ukMany: "") == "3 гаманці")
        #expect(L10n.plural(4, englishOne: "", englishOther: "", ukOne: "", ukFew: "%d гаманці", ukMany: "") == "4 гаманці")
        #expect(L10n.plural(22, englishOne: "", englishOther: "", ukOne: "", ukFew: "%d гаманці", ukMany: "") == "22 гаманці")
    }

    @Test func pluralUkrainianMany() {
        let key = AppLanguagePreference.storageKey
        let prior = UserDefaults.standard.string(forKey: key)
        UserDefaults.standard.set("uk", forKey: key)
        defer {
            if let prior {
                UserDefaults.standard.set(prior, forKey: key)
            } else {
                UserDefaults.standard.removeObject(forKey: key)
            }
        }
        #expect(L10n.plural(5, englishOne: "", englishOther: "", ukOne: "", ukFew: "", ukMany: "%d гаманців") == "5 гаманців")
        #expect(L10n.plural(10, englishOne: "", englishOther: "", ukOne: "", ukFew: "", ukMany: "%d гаманців") == "10 гаманців")
        #expect(L10n.plural(11, englishOne: "", englishOther: "", ukOne: "", ukFew: "", ukMany: "%d гаманців") == "11 гаманців")
        #expect(L10n.plural(12, englishOne: "", englishOther: "", ukOne: "", ukFew: "", ukMany: "%d гаманців") == "12 гаманців")
        #expect(L10n.plural(13, englishOne: "", englishOther: "", ukOne: "", ukFew: "", ukMany: "%d гаманців") == "13 гаманців")
        #expect(L10n.plural(14, englishOne: "", englishOther: "", ukOne: "", ukFew: "", ukMany: "%d гаманців") == "14 гаманців")
        #expect(L10n.plural(20, englishOne: "", englishOther: "", ukOne: "", ukFew: "", ukMany: "%d гаманців") == "20 гаманців")
        #expect(L10n.plural(25, englishOne: "", englishOther: "", ukOne: "", ukFew: "", ukMany: "%d гаманців") == "25 гаманців")
    }

    // MARK: - L10n count helpers (English default)

    @Test func walletCountEnglish() {
        #expect(L10n.walletCount(1) == "1 wallet")
        #expect(L10n.walletCount(5) == "5 wallets")
    }

    @Test func labelCountEnglish() {
        #expect(L10n.labelCount(1) == "1 label")
        #expect(L10n.labelCount(0) == "0 labels")
    }

    @Test func templateCountEnglish() {
        #expect(L10n.templateCount(1) == "1 template")
        #expect(L10n.templateCount(3) == "3 templates")
    }

    @Test func transactionCountEnglish() {
        #expect(L10n.transactionCount(1) == "1 transaction")
        #expect(L10n.transactionCount(10) == "10 transactions")
    }

    @Test func cardCountEnglish() {
        #expect(L10n.cardCount(1) == "1 card")
        #expect(L10n.cardCount(7) == "7 cards")
    }

    @Test func rowCountEnglish() {
        #expect(L10n.rowCount(1) == "1 row")
        #expect(L10n.rowCount(100) == "100 rows")
    }

    // MARK: - BuiltInCategoryDisplayName

    @Test func builtInCategoryDisplayNameReturnsLocalizedKeyForKnownUUID() {
        let groceriesID = UUID(uuidString: "11111111-1111-1111-1111-111111111111")!
        let result = BuiltInCategoryDisplayName.name(id: groceriesID, fallback: "Fallback")
        // In the test bundle, L10n.string returns the key value (fallback to key)
        #expect(result == "category.groceries")
    }

    @Test func builtInCategoryDisplayNameReturnsFallbackForUnknownUUID() {
        let unknownID = UUID(uuidString: "00000000-0000-0000-0000-000000000000")!
        let result = BuiltInCategoryDisplayName.name(id: unknownID, fallback: "Custom Category")
        #expect(result == "Custom Category")
    }

    @Test func builtInCategoryDisplayNameUsesEmptyFallbackForUnknownUUID() {
        let unknownID = UUID(uuidString: "FFFFFFFF-FFFF-FFFF-FFFF-FFFFFFFFFFFF")!
        let result = BuiltInCategoryDisplayName.name(id: unknownID, fallback: "")
        #expect(result == "")
    }
}
