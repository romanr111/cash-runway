import Foundation
import SwiftUI
import CashRunwayCore

struct WalletManagementView: View {
    @Environment(\.dismiss) private var dismiss
    @Bindable var model: CashRunwayAppModel
    @State private var isEditorPresented = false
    @State private var walletDraft = Wallet(id: UUID(), name: "", kind: .cash, colorHex: "#60788A", iconName: "wallet.pass.fill", startingBalanceMinor: 0, currentBalanceMinor: 0, isArchived: false, sortOrder: 0, createdAt: .now, updatedAt: .now)

    var body: some View {
        NavigationStack {
            List {
                EmptyView().accessibilityIdentifier(CashRunwayAccessibilityID.walletManagementScreen)
                ForEach(model.wallets) { wallet in
                    Button(wallet.name) {
                        walletDraft = wallet
                        isEditorPresented = true
                    }
                    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                        if model.wallets.count > 1 {
                            Button(role: .destructive) {
                                model.deleteWallet(id: wallet.id)
                            } label: {
                                SwiftUI.Label("Delete", systemImage: "trash")
                            }
                        }
                    }
                }
            }
            .navigationTitle("Manual Wallets")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Done") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        walletDraft = Wallet(
                            id: UUID(),
                            name: "",
                            kind: .cash,
                            colorHex: "#60788A",
                            iconName: "wallet.pass.fill",
                            startingBalanceMinor: 0,
                            currentBalanceMinor: 0,
                            currencyCode: model.defaultCurrencyCode,
                            isArchived: false,
                            sortOrder: model.wallets.count,
                            createdAt: .now,
                            updatedAt: .now
                        )
                        isEditorPresented = true
                    } label: {
                        Image(systemName: "plus")
                    }
                }
            }
            .sheet(isPresented: $isEditorPresented) {
                WalletEditorView(model: model, wallet: $walletDraft)
            }
        }
    }
}
