import Foundation
import SwiftUI
import CashRunwayCore

struct WalletEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @Bindable var model: CashRunwayAppModel
    @Binding var wallet: Wallet
    @State private var balanceText = ""
    @State private var showsDeleteConfirmation = false
    @State private var isNewCategorySheetPresented = false
    @State private var previousCategoryID: UUID?

    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 18) {
                    CashRunwaySurface {
                        HStack(spacing: 16) {
                            CategoryGlyph(iconName: wallet.iconName ?? "wallet.pass.fill", colorHex: wallet.colorHex ?? "#60788A", size: 64)
                            VStack(alignment: .leading, spacing: 4) {
                                Text(wallet.name.isEmpty ? L10n.string("New Wallet") : wallet.name)
                                    .font(CashRunwayTheme.headingFont)
                                    .foregroundStyle(CashRunwayTheme.textPrimary)
                                    .lineLimit(1)
                                Text(walletCategoryDisplayName)
                                    .font(CashRunwayTheme.bodyFont)
                                    .foregroundStyle(CashRunwayTheme.textSecondary)
                            }
                        }
                    }

                    VStack(alignment: .leading, spacing: 14) {
                        Text(L10n.string("Wallet Details"))
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(CashRunwayTheme.textMuted)
                            .textCase(.uppercase)
                        VStack(spacing: 14) {
                            TextField(L10n.string("Name"), text: $wallet.name)
                                .textFieldStyle(.roundedBorder)
                            Picker(L10n.string("Wallet Category"), selection: $wallet.categoryID) {
                                ForEach(model.walletCategories, id: \.id) { category in
                                    Text(category.displayName).tag(category.id)
                                }
                                Text(L10n.string("New Wallet Category"))
                                    .tag(WalletCategory.newCategoryActionID)
                            }
                            .onChange(of: wallet.categoryID) { oldValue, newValue in
                                if newValue == WalletCategory.newCategoryActionID {
                                    previousCategoryID = oldValue
                                    isNewCategorySheetPresented = true
                                } else if let category = model.walletCategories.first(where: { $0.id == newValue }) {
                                    wallet.kind = category.kind
                                }
                            }
                            Picker(L10n.string("Currency"), selection: $wallet.currencyCode) {
                                ForEach(SupportedCurrency.allCases, id: \.currencyCode) { currency in
                                    Text(currency.displayName).tag(currency.currencyCode)
                                }
                            }
                            .disabled(!canChangeCurrency)
                            if !canChangeCurrency {
                                Text(L10n.string("Currency cannot be changed after ledger or bank data exists."))
                                    .font(.system(size: 13, weight: .medium))
                                    .foregroundStyle(CashRunwayTheme.textMuted)
                            }
                            TextField(L10n.string("Starting Balance"), text: $balanceText)
                                .keyboardType(.decimalPad)
                                .textFieldStyle(.roundedBorder)
                        }
                        .ledgerSurface()
                    }

                    if model.wallets.count > 1 {
                        Button(role: .destructive) {
                            showsDeleteConfirmation = true
                        } label: {
                            SwiftUI.Label(L10n.string("Delete Wallet"), systemImage: "trash")
                                .font(.system(size: 16, weight: .semibold))
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 14)
                                .background(CashRunwayTheme.negative.opacity(0.10), in: Capsule())
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 16)
            }
            .background(CashRunwayTheme.background)
            .navigationTitle(L10n.string("Wallet"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { Button(L10n.string("Cancel")) { dismiss() } }
                ToolbarItem(placement: .topBarTrailing) {
                    Button(L10n.string("Save")) {
                        let balance = (try? MoneyFormatter.parseMinorUnits(balanceText)) ?? 0
                        wallet.startingBalanceMinor = balance
                        wallet.currentBalanceMinor = balance
                        wallet.updatedAt = .now
                        if model.saveWallet(wallet) {
                            dismiss()
                        }
                    }
                }
            }
            .alert(L10n.string("Delete Wallet?"), isPresented: $showsDeleteConfirmation) {
                Button(L10n.string("Cancel"), role: .cancel) {}
                Button(L10n.string("Delete"), role: .destructive) {
                    model.deleteWallet(id: wallet.id)
                    dismiss()
                }
            } message: {
                Text(L10n.string("This will permanently remove the wallet and all of its transactions."))
            }
        }
        .onAppear {
            balanceText = wallet.startingBalanceMinor == 0 ? "" : MoneyFormatter.plainString(from: wallet.startingBalanceMinor)
        }
        .sheet(
            isPresented: $isNewCategorySheetPresented,
            onDismiss: {
                if wallet.categoryID == WalletCategory.newCategoryActionID {
                    wallet.categoryID = previousCategoryID ?? WalletCategory.builtIn(byKind: wallet.kind).id
                }
            },
            content: {
                NewWalletCategorySheet(
                    model: model,
                    onSave: { category in
                        wallet.categoryID = category.id
                        wallet.kind = category.kind
                        previousCategoryID = category.id
                    },
                    onCancel: {
                        wallet.categoryID = previousCategoryID ?? WalletCategory.builtIn(byKind: wallet.kind).id
                    }
                )
            }
        )
    }

    private var walletCategoryDisplayName: String {
        model.walletCategories.first { $0.id == wallet.categoryID }?.displayName
            ?? L10n.walletKind(wallet.kind)
    }

    private var canChangeCurrency: Bool {
        model.canChangeWalletCurrency(wallet.id)
    }
}

struct NewWalletCategorySheet: View {
    @Environment(\.dismiss) private var dismiss
    @Bindable var model: CashRunwayAppModel
    let onSave: (WalletCategory) -> Void
    let onCancel: () -> Void
    @State private var name = ""

    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: CashRunwayTheme.spaceXL) {
                    previewCard
                    inputSection
                }
                .padding(.horizontal, CashRunwayTheme.spaceM)
                .padding(.top, CashRunwayTheme.spaceL)
            }
            .background(CashRunwayTheme.background)
            .navigationTitle(L10n.string("New Wallet Category"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(L10n.string("Cancel")) {
                        onCancel()
                        dismiss()
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button(L10n.string("Save")) {
                        saveCategory()
                    }
                    .disabled(trimmedName.isEmpty)
                }
            }
        }
    }

    private var previewCard: some View {
        CashRunwaySurface {
            HStack(spacing: CashRunwayTheme.spaceM) {
                CategoryGlyph(iconName: "wallet.pass.fill", colorHex: "#60788A", size: 64)
                Text(previewName)
                    .font(CashRunwayTheme.headingFont)
                    .foregroundStyle(CashRunwayTheme.textPrimary)
                    .lineLimit(1)
                Spacer()
            }
            .accessibilityElement(children: .combine)
        }
    }

    private var inputSection: some View {
        VStack(alignment: .leading, spacing: CashRunwayTheme.spaceS) {
            Text(L10n.string("Category Name").uppercased(with: L10n.locale))
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(CashRunwayTheme.textMuted)
            TextField(L10n.string("Category Name"), text: $name)
                .textFieldStyle(.roundedBorder)
                .font(CashRunwayTheme.bodyFont)
        }
        .ledgerSurface()
    }

    private var trimmedName: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var previewName: String {
        trimmedName.isEmpty ? L10n.string("New Wallet Category") : trimmedName
    }

    private func saveCategory() {
        let category = WalletCategory(
            id: UUID(),
            name: trimmedName,
            kind: .other,
            isSystem: false,
            createdAt: .now,
            updatedAt: .now
        )
        let saved = model.saveWalletCategory(category)
        if saved {
            onSave(category)
            dismiss()
        }
    }
}
