import Foundation
import SwiftUI
import CashRunwayCore

struct WalletManagementView: View {
    @Environment(\.dismiss) private var dismiss
    @Bindable var model: CashRunwayAppModel
    @State private var isEditorPresented = false
    @State private var walletDraft = Wallet(id: UUID(), name: "", kind: .cash, colorHex: "#60788A", iconName: "wallet.pass.fill", startingBalanceMinor: 0, currentBalanceMinor: 0, isArchived: false, sortOrder: 0, createdAt: .now, updatedAt: .now)

    private var operationalWallets: [Wallet] {
        model.wallets.filter { !$0.isExcludedFromSummary }
    }

    private var savingsWallets: [Wallet] {
        model.wallets.filter { $0.isExcludedFromSummary }
    }

    var body: some View {
        NavigationStack {
            List {
                EmptyView().accessibilityIdentifier(CashRunwayAccessibilityID.walletManagementScreen)
                Section(header: Text(L10n.string("Manual Wallets"))) {
                    ForEach(operationalWallets) { wallet in
                        walletRow(wallet)
                    }
                }
                if !savingsWallets.isEmpty {
                    Section(header: Text(L10n.string("Savings Section"))) {
                        ForEach(savingsWallets) { wallet in
                            walletRow(wallet, isSavings: true)
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

    private func walletRow(_ wallet: Wallet, isSavings: Bool = false) -> some View {
        Button {
            walletDraft = wallet
            isEditorPresented = true
        } label: {
            HStack(spacing: 12) {
                if isSavings {
                    CategoryGlyph(
                        iconName: wallet.iconName ?? "wallet.pass.fill",
                        colorHex: wallet.colorHex ?? "#E99A31",
                        size: 28
                    )
                }
                Text(wallet.name)
                if isSavings {
                    Spacer(minLength: 8)
                    Text(L10n.walletKind(wallet.kind))
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(CashRunwayTheme.textMuted)
                    Image(systemName: "chart.line.uptrend.xyaxis")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(CashRunwayTheme.textMuted)
                }
            }
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