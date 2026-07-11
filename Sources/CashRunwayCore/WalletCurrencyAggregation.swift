import Foundation

public extension Array where Element == Wallet {
    /// Returns the single currency code that can be used for all-wallet aggregates.
    ///
    /// - If a specific wallet is selected, returns that wallet's currency.
    /// - If no wallet is selected, only active (non-archived) wallets are considered.
    ///   If all active wallets share one currency, that currency is returned.
    ///   Otherwise returns `nil`, meaning all-wallet aggregates are unsafe.
    func aggregateCurrencyCode(selectedWalletID: UUID?) -> CurrencyCode? {
        if let selectedWalletID, let selectedWallet = first(where: { $0.id == selectedWalletID }) {
            return selectedWallet.currencyCode
        }

        let activeWallets = filter { !$0.isArchived }
        let currencyCodes = Set(activeWallets.map(\.currencyCode))
        return currencyCodes.count == 1 ? currencyCodes.first : nil
    }
}
