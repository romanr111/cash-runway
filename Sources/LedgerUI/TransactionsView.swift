import SwiftUI
#if canImport(LedgerCore)
import LedgerCore
#endif

struct TransactionsView: View {
    @Bindable var model: LedgerAppModel
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
                            .foregroundStyle(LedgerTheme.textPrimary)

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
                                            .foregroundStyle(LedgerTheme.textPrimary)
                                        Text(wallet.kind.rawValue.capitalized)
                                            .font(.system(size: 14, weight: .medium))
                                            .foregroundStyle(LedgerTheme.textSecondary)
                                    }
                                    Spacer()
                                    VStack(alignment: .trailing, spacing: 3) {
                                        Text(MoneyFormatter.string(from: wallet.currentBalanceMinor))
                                            .font(.system(size: 17, weight: .semibold))
                                            .foregroundStyle(wallet.currentBalanceMinor < 0 ? LedgerTheme.negative : LedgerTheme.textPrimary)
                                        Image(systemName: "chevron.right")
                                            .font(.system(size: 13, weight: .bold))
                                            .foregroundStyle(LedgerTheme.textMuted)
                                    }
                                }
                                .padding(18)
                                .background(LedgerTheme.surface, in: RoundedRectangle(cornerRadius: 26, style: .continuous))
                                .overlay(RoundedRectangle(cornerRadius: 26, style: .continuous).stroke(LedgerTheme.line, lineWidth: 1))
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
                        .foregroundStyle(LedgerTheme.textPrimary)
                        .padding(.horizontal, 18)
                        .padding(.vertical, 14)
                        .background(LedgerTheme.pill, in: Capsule())
                    }
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 16)
                .padding(.bottom, 40)
            }
            .background(LedgerTheme.background)
            .sheet(isPresented: $isWalletEditorPresented) {
                WalletEditorView(model: model, wallet: $walletDraft)
            }
        }
    }

    private var balanceCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Total Wealth")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(LedgerTheme.textSecondary)
            Text(MoneyFormatter.string(from: model.overviewSnapshot?.totalWealthMinor ?? 0))
                .font(.system(size: 34, weight: .bold, design: .rounded))
                .foregroundStyle(LedgerTheme.textPrimary)
            Text("\(model.wallets.count) wallets")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(LedgerTheme.textMuted)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(22)
        .background(LedgerTheme.surface, in: RoundedRectangle(cornerRadius: 30, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 30, style: .continuous).stroke(LedgerTheme.line, lineWidth: 1))
    }
}

struct TransactionRow: View {
    let item: TransactionListItem

    var body: some View {
        HStack(spacing: 14) {
            CategoryGlyph(iconName: item.categoryIconName ?? fallbackIcon, colorHex: item.categoryColorHex ?? fallbackColor, size: 52)
            VStack(alignment: .leading, spacing: 3) {
                Text(item.merchant)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(LedgerTheme.textPrimary)
                Text(item.walletName)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(LedgerTheme.textSecondary)
                if !item.note.isEmpty {
                    Text(item.note)
                        .font(.system(size: 13))
                        .foregroundStyle(LedgerTheme.textMuted)
                        .lineLimit(2)
                }
                if !item.labels.isEmpty {
                    Text(item.labels.map(\.name).joined(separator: " • "))
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(LedgerTheme.accentDark)
                        .lineLimit(1)
                }
            }
            Spacer()
            Text(MoneyFormatter.string(from: item.amountMinor))
                .font(.system(size: 17, weight: .bold))
                .foregroundStyle(LedgerTheme.amountColor(item.amountMinor))
                .multilineTextAlignment(.trailing)
        }
        .padding(.vertical, 6)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(item.merchant), \(MoneyFormatter.string(from: item.amountMinor)), \(item.walletName)")
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

struct TransactionDetailsView: View {
    let item: TransactionListItem
    @Bindable var model: LedgerAppModel
    let onEdit: () -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section("Summary") {
                    detailRow("Amount", MoneyFormatter.string(from: item.amountMinor))
                    detailRow("Wallet", item.walletName)
                    detailRow("Type", item.kind.rawValue.capitalized)
                    detailRow("Date", item.occurredAt.formatted(date: .abbreviated, time: .omitted))
                    detailRow("Source", item.source.rawValue.replacingOccurrences(of: "_", with: " ").capitalized)
                }
                if let categoryName = item.categoryName {
                    Section("Category") {
                        detailRow("Category", categoryName)
                    }
                }
                if !item.labels.isEmpty {
                    Section("Labels") {
                        Text(item.labels.map(\.name).joined(separator: ", "))
                    }
                }
                if !item.note.isEmpty {
                    Section("Note") {
                        Text(item.note)
                    }
                }
                Section {
                    Button("Edit", action: onEdit)
                    Button("Delete", role: .destructive) {
                        model.deleteTransaction(id: item.id)
                        dismiss()
                    }
                }
            }
            .navigationTitle(item.merchant)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    private func detailRow(_ title: String, _ value: String) -> some View {
        HStack {
            Text(title)
                .foregroundStyle(LedgerTheme.textSecondary)
            Spacer()
            Text(value)
        }
    }
}
