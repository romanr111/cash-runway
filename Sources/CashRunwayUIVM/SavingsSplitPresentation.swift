import CashRunwayCore

/// Pure presentation helpers for the separate-entity savings wallet split.
public enum SavingsSplitPresentation {
    /// Wallets whose balance is excluded from every shared aggregate.
    public static func savingsWallets(in wallets: [Wallet]) -> [Wallet] {
        wallets.filter { $0.isExcludedFromSummary }
    }

    /// Active, shared-aggregate wallets.
    public static func operationalWallets(in wallets: [Wallet]) -> [Wallet] {
        wallets.filter { !$0.isExcludedFromSummary }
    }

    /// Sums savings current balances when all savings wallets share one currency;
    /// `nil` when mixed currencies make a single total unsafe, or when there are
    /// no savings wallets (the dashboard hides the strip).
    public static func savingsTotalMinor(in wallets: [Wallet]) -> Int64? {
        let savings = savingsWallets(in: wallets)
        guard !savings.isEmpty else { return nil }
        let currencyCodes = Set(savings.map(\.currencyCode))
        guard currencyCodes.count == 1 else { return nil }
        return savings.reduce(Int64.zero) { $0 + $1.currentBalanceMinor }
    }
}
