import SwiftUI
import CashRunwayCore

struct TransactionsView: View {
    @Bindable var model: CashRunwayAppModel
    @State private var isWalletEditorPresented = false
    @State private var walletDraft = Wallet(id: UUID(), name: "", kind: .cash, colorHex: "#60788A", iconName: "wallet.pass.fill", startingBalanceMinor: 0, currentBalanceMinor: 0, isArchived: false, sortOrder: 0, createdAt: .now, updatedAt: .now)

    private func walletCategoryDisplayName(for wallet: Wallet) -> String {
        model.walletCategories.first { $0.id == wallet.categoryID }?.displayName
            ?? L10n.walletKind(wallet.kind)
    }

    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 22) {
                    ScreenTitle(title: "Wallets")

                    balanceCard

                    VStack(alignment: .leading, spacing: 14) {
                        Text("Manual Wallets")
                            .font(.system(size: 20, weight: .bold, design: .rounded))
                            .foregroundStyle(CashRunwayTheme.textPrimary)

                        if model.hasBootstrapped && model.wallets.isEmpty {
                            ContentUnavailableView(
                                "Create a wallet to start tracking transactions",
                                systemImage: "wallet.pass.fill",
                                description: Text("Tap Add Wallet below to get started.")
                            )
                            .padding(.top, 20)
                        }

                        ForEach(model.wallets) { wallet in
                            Button {
                                walletDraft = wallet
                                isWalletEditorPresented = true
                            } label: {
                                HStack(spacing: 14) {
                                    CategoryGlyph(iconName: wallet.iconName ?? "wallet.pass.fill", colorHex: wallet.colorHex ?? "#60788A", size: 50)
                                    VStack(alignment: .leading, spacing: 3) {
                                        Text(wallet.name)
                                            .font(.system(size: 17, weight: .semibold))
                                            .foregroundStyle(CashRunwayTheme.textPrimary)
                                        Text(walletCategoryDisplayName(for: wallet))
                                            .font(.system(size: 14, weight: .medium))
                                            .foregroundStyle(CashRunwayTheme.textSecondary)
                                    }
                                    Spacer()
                                    VStack(alignment: .trailing, spacing: 3) {
            Text(MoneyFormatter.string(from: wallet.currentBalanceMinor, currencyCode: wallet.currencyCode))
                                            .font(.system(size: 17, weight: .semibold))
                                            .foregroundStyle(wallet.currentBalanceMinor < 0 ? CashRunwayTheme.negative : CashRunwayTheme.textPrimary)
                                        Image(systemName: "chevron.right")
                                            .font(.system(size: 13, weight: .bold))
                                            .foregroundStyle(CashRunwayTheme.textMuted)
                                    }
                                }
                                .padding(18)
                                .background(CashRunwayTheme.surface, in: RoundedRectangle(cornerRadius: 26, style: .continuous))
                                .overlay(RoundedRectangle(cornerRadius: 26, style: .continuous).stroke(CashRunwayTheme.line, lineWidth: 1))
                            }
                            .buttonStyle(.plain)
                        }
                    }

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
                        isWalletEditorPresented = true
                    } label: {
                        HStack {
                            Image(systemName: "plus.circle.fill")
                            Text("Add Wallet")
                        }
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(CashRunwayTheme.textPrimary)
                        .padding(.horizontal, 18)
                        .padding(.vertical, 14)
                        .background(CashRunwayTheme.pill, in: Capsule())
                    }
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 16)
                .padding(.bottom, 40)
            }
            .background(CashRunwayTheme.background)
            .sheet(isPresented: $isWalletEditorPresented) {
                WalletEditorView(model: model, wallet: $walletDraft)
            }
        }
    }

    private var balanceCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Total Wealth")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(CashRunwayTheme.textSecondary)
            if let wealthText = model.aggregateMoneyString(from: model.overviewSnapshot?.totalWealthMinor ?? 0) {
                Text(wealthText)
                    .font(.system(size: 34, weight: .bold, design: .rounded))
                    .foregroundStyle(CashRunwayTheme.textPrimary)
            } else {
                Text("Mixed-currency totals unavailable")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(CashRunwayTheme.textMuted)
            }
            Text(L10n.walletCount(model.wallets.count))
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(CashRunwayTheme.textMuted)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(22)
        .background(CashRunwayTheme.surface, in: RoundedRectangle(cornerRadius: 30, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 30, style: .continuous).stroke(CashRunwayTheme.line, lineWidth: 1))
    }
}

struct TransactionRow: View {
    let item: TransactionListItem

    var body: some View {
        HStack(spacing: 14) {
            CategoryGlyph(iconName: item.categoryIconName ?? fallbackIcon, colorHex: item.categoryColorHex ?? fallbackColor, size: 52)
            VStack(alignment: .leading, spacing: 4) {
                Text(primaryTitle)
                    .font(CashRunwayTheme.subheadingFont)
                    .foregroundStyle(CashRunwayTheme.textPrimary)
                    .lineLimit(1)
                    .truncationMode(.tail)
                Text(secondaryTitle)
                    .font(CashRunwayTheme.captionFont)
                    .foregroundStyle(CashRunwayTheme.textSecondary)
                    .lineLimit(1)
                if !note.isEmpty {
                    Text(note)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(CashRunwayTheme.textSecondary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
                HStack(spacing: 6) {
                    ForEach(Array(metadataParts.enumerated()), id: \.offset) { index, part in
                        if index > 0 {
                            Text("·")
                        }
                        Text(part)
                    }
                }
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(CashRunwayTheme.textMuted)
                .lineLimit(1)
            }
            Spacer()
            Text(MoneyFormatter.string(from: item.amountMinor, currencyCode: item.currencyCode))
                .font(.system(size: 17, weight: .bold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(CashRunwayTheme.amountColor(item.amountMinor))
                .multilineTextAlignment(.trailing)
                .lineLimit(1)
                .minimumScaleFactor(0.72)
        }
        .padding(.vertical, 8)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilitySummary)
    }

    private var primaryTitle: String {
        item.merchant.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? item.displayTitle : item.merchant
    }

    private var localizedCategoryName: String? {
        guard let categoryName = item.categoryName, !categoryName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return nil
        }
        return item.categoryID.map { BuiltInCategoryDisplayName.name(id: $0, fallback: categoryName) } ?? categoryName
    }

    private var secondaryTitle: String {
        let merchantIsEmpty = item.merchant.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        if let localized = localizedCategoryName, !(merchantIsEmpty && localized == primaryTitle) {
            return "\(localized) · \(item.walletName)"
        }
        return item.walletName
    }

    private var note: String {
        item.note.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var metadataParts: [String] {
        var parts: [String] = []
        parts.append(item.occurredAt.formatted(date: .abbreviated, time: .omitted))
        parts.append(item.source.displayName)
        if !item.labels.isEmpty {
            parts.append(item.labels.map(\.name).joined(separator: ", "))
        }
        return parts
    }

    private var accessibilitySummary: String {
        var components = [item.displayTitle, MoneyFormatter.string(from: item.amountMinor, currencyCode: item.currencyCode), item.walletName]
        if !note.isEmpty {
            components.append(note)
        }
        components.append(contentsOf: metadataParts)
        return components.joined(separator: ", ")
    }

    private var fallbackColor: String {
        item.kind == .income ? "#1CC389" : "#60788A"
    }

    private var fallbackIcon: String {
        switch item.kind {
        case .expense: "creditcard.fill"
        case .income: "banknote.fill"
        case .transfer: "arrow.left.arrow.right"
        }
    }
}
