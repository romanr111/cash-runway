import SwiftUI
#if canImport(CashRunwayCore)
import CashRunwayCore
#endif

struct TransactionsView: View {
    @Bindable var model: CashRunwayAppModel
    @State private var isWalletEditorPresented = false
    @State private var walletDraft = Wallet(id: UUID(), name: "", kind: .cash, colorHex: "#60788A", iconName: "wallet.pass.fill", startingBalanceMinor: 0, currentBalanceMinor: 0, isArchived: false, sortOrder: 0, createdAt: .now, updatedAt: .now)

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
                                        Text(wallet.kind.rawValue.capitalized)
                                            .font(.system(size: 14, weight: .medium))
                                            .foregroundStyle(CashRunwayTheme.textSecondary)
                                    }
                                    Spacer()
                                    VStack(alignment: .trailing, spacing: 3) {
                                        Text(MoneyFormatter.string(from: wallet.currentBalanceMinor))
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
            Text(MoneyFormatter.string(from: model.overviewSnapshot?.totalWealthMinor ?? 0))
                .font(.system(size: 34, weight: .bold, design: .rounded))
                .foregroundStyle(CashRunwayTheme.textPrimary)
            Text("\(model.wallets.count) wallets")
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
            Text(MoneyFormatter.string(from: item.amountMinor))
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

    private var secondaryTitle: String {
        if let categoryName = item.categoryName, !categoryName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return "\(categoryName) · \(item.walletName)"
        }
        return item.walletName
    }

    private var metadataParts: [String] {
        var parts: [String] = []
        let note = item.note.trimmingCharacters(in: .whitespacesAndNewlines)
        if !note.isEmpty {
            parts.append(note)
        }
        parts.append(item.occurredAt.formatted(date: .abbreviated, time: .omitted))
        parts.append(item.source.rawValue.replacingOccurrences(of: "_", with: " ").capitalized)
        if !item.labels.isEmpty {
            parts.append(item.labels.map(\.name).joined(separator: ", "))
        }
        return parts
    }

    private var accessibilitySummary: String {
        ([item.displayTitle, MoneyFormatter.string(from: item.amountMinor), item.walletName] + metadataParts).joined(separator: ", ")
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
