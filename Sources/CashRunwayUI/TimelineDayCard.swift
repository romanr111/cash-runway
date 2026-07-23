import CashRunwayCore
import SwiftUI

/// Day card for the redesigned Timeline feed.
///
/// Wraps a `TimelineSection` in a surface card with a header that shows the day,
/// total, and an expand/collapse chevron. Tapping the header toggles collapse state.
/// Transaction rows reuse `TransactionRow` and preserve editor navigation.
struct TimelineDayCard: View {
    let section: TimelineSection
    let totalText: String?
    let isMixedCurrency: Bool
    let onSelectItem: (TransactionListItem) -> Void
    @Binding var isCollapsed: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    isCollapsed.toggle()
                }
            } label: {
                dayHeader
            }
            .buttonStyle(.plain)
            .accessibilityElement(children: .combine)
            .accessibilityLabel(dayAccessibilityLabel)
            .accessibilityHint(collapsedAccessibilityHint)
            .accessibilityIdentifier(CashRunwayAccessibilityID.timelineDayHeader(section.periodKey))
            .accessibilityAddTraits(.isButton)

            if !isCollapsed {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(section.items.enumerated()), id: \.offset) { index, item in
                        Button {
                            onSelectItem(item)
                        } label: {
                            TimelineCompactRow(item: item)
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier(CashRunwayAccessibilityID.transactionRow(item))

                        if index != section.items.count - 1 {
                            Divider()
                                .overlay(CashRunwayTheme.line)
                                .padding(.leading, 66)
                        }
                    }
                }
                .padding(.vertical, 12)
                .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(CashRunwayTheme.surface, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .contentShape(Rectangle())
    }

    private var dayHeader: some View {
        HStack(alignment: .center, spacing: 12) {
            Image(systemName: "calendar")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(CashRunwayTheme.textMuted)
                .frame(width: 24, height: 24)

            Text(CashRunwayTheme.dayHeader(for: section.periodKey))
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(CashRunwayTheme.textPrimary)

            Spacer()

            if isMixedCurrency {
                Text(L10n.string("Mixed-currency totals unavailable"))
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(CashRunwayTheme.textMuted)
            } else if let totalText {
                Text(totalText)
                    .font(.system(size: 15, weight: .semibold).monospacedDigit())
                    .foregroundStyle(CashRunwayTheme.amountColor(section.totalMinor))
            }

            Image(systemName: isCollapsed ? "chevron.down" : "chevron.up")
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(CashRunwayTheme.textMuted)
                .frame(width: 24, height: 24)
                .accessibilityIdentifier(CashRunwayAccessibilityID.timelineDayToggle(section.periodKey))
        }
        .frame(minHeight: 44)
        .contentShape(Rectangle())
    }

    private var dayAccessibilityLabel: String {
        let date = CashRunwayTheme.dayHeader(for: section.periodKey)
        let total: String
        if isMixedCurrency {
            total = L10n.string("Mixed-currency totals unavailable")
        } else if let totalText {
            total = totalText
        } else {
            total = MoneyFormatter.string(from: section.totalMinor, currencyCode: .uah)
        }
        let state = isCollapsed ? L10n.string("timeline.accessibility.expand") : L10n.string("timeline.accessibility.collapse")
        return "\(date), \(total), \(state)"
    }

    private var collapsedAccessibilityHint: String {
        isCollapsed
            ? L10n.string("timeline.accessibility.expand")
            : L10n.string("timeline.accessibility.collapse")
    }
}

/// Compact transaction row for Timeline day cards.
///
/// Keeps the title, category/metadata, and amount on a tight two-line layout so day
/// cards remain scannable when stacked.
private struct TimelineCompactRow: View {
    let item: TransactionListItem

    var body: some View {
        HStack(alignment: .center, spacing: 14) {
            CategoryGlyph(iconName: item.categoryIconName ?? fallbackIcon, colorHex: item.categoryColorHex ?? fallbackColor, size: 44)

            VStack(alignment: .leading, spacing: 2) {
                Text(primaryTitle)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(CashRunwayTheme.textPrimary)
                    .lineLimit(1)
                    .truncationMode(.tail)

                Text(secondaryTitle)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(CashRunwayTheme.textSecondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }

            Spacer()

            Text(MoneyFormatter.string(from: item.amountMinor, currencyCode: item.currencyCode))
                .font(.system(size: 16, weight: .bold, design: .rounded).monospacedDigit())
                .foregroundStyle(CashRunwayTheme.amountColor(item.amountMinor))
                .multilineTextAlignment(.trailing)
                .lineLimit(1)
                .minimumScaleFactor(0.75)

            Image(systemName: "chevron.right")
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(CashRunwayTheme.textMuted)
        }
        .padding(.vertical, 8)
        .contentShape(Rectangle())
    }

    private var primaryTitle: String {
        item.merchant.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? item.displayTitle
            : item.merchant
    }

    private var localizedCategoryName: String? {
        guard let categoryName = item.categoryName,
              !categoryName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return nil
        }
        return item.categoryID.map { BuiltInCategoryDisplayName.name(id: $0, fallback: categoryName) } ?? categoryName
    }

    private var secondaryTitle: String {
        var parts: [String] = []
        if let category = localizedCategoryName, category != primaryTitle {
            parts.append(category)
        }
        if !item.note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            parts.append(item.note.trimmingCharacters(in: .whitespacesAndNewlines))
        }
        return parts.isEmpty ? item.walletName : parts.joined(separator: " · ")
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
