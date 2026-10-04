import Foundation
import Testing
import CashRunwayCore
@testable import CashRunwayUIVM

struct SavingsSplitPresentationTests {
    private func wallet(_ name: String, kind: WalletKind, currency: CurrencyCode, current: Int64, excluded: Bool) -> Wallet {
        var w = Wallet(
            id: UUID(), name: name, kind: kind, colorHex: nil, iconName: nil,
            startingBalanceMinor: current, currentBalanceMinor: current,
            currencyCode: currency, isArchived: false, isExcludedFromSummary: excluded,
            sortOrder: 0, createdAt: .now, updatedAt: .now
        )
        w.isExcludedFromSummary = excluded
        return w
    }

    @Test func splitSplitsByFlag() {
        let ops = wallet("A", kind: .card, currency: .uah, current: 100, excluded: false)
        let savings = wallet("S", kind: .savings, currency: .uah, current: 900, excluded: true)
        let wallets = [ops, savings]
        #expect(SavingsSplitPresentation.savingsWallets(in: wallets) == [savings])
        #expect(SavingsSplitPresentation.operationalWallets(in: wallets) == [ops])
    }

    @Test func totalNilWhenNoSavingsWallets() {
        let ops = wallet("A", kind: .card, currency: .uah, current: 100, excluded: false)
        #expect(SavingsSplitPresentation.savingsTotalMinor(in: [ops]) == nil)
    }

    @Test func totalSumsSameCurrencySavings() {
        let s1 = wallet("S1", kind: .savings, currency: .uah, current: 100, excluded: true)
        let s2 = wallet("S2", kind: .savings, currency: .uah, current: 250, excluded: true)
        #expect(SavingsSplitPresentation.savingsTotalMinor(in: [s1, s2]) == 350)
    }

    @Test func totalNilForMixedCurrencySavings() {
        let s1 = wallet("S1", kind: .savings, currency: .uah, current: 100, excluded: true)
        let s2 = wallet("S2", kind: .savings, currency: .usd, current: 250, excluded: true)
        #expect(SavingsSplitPresentation.savingsTotalMinor(in: [s1, s2]) == nil)
    }
}
