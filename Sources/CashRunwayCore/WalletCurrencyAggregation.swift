import Foundation

public extension Array where Element == Wallet {
    func aggregateCurrencyCode(selectedWalletID: UUID?) -> CurrencyCode? {
        if let selectedWalletID, let selectedWallet = first(where: { $0.id == selectedWalletID }) {
            return selectedWallet.currencyCode
        }

        let currencyCodes = Set(map(\.currencyCode))
        return currencyCodes.count == 1 ? currencyCodes.first : nil
    }
}
