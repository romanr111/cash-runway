import CashRunwayCore
import CashRunwayUIVM
import SwiftUI

struct TimelineSummaryCard: View {
    let presentation: TimelinePresentation
    let period: TimelinePeriod
    let locale: Locale
    let onSelectPeriod: (Int) -> Void

    private let pageHorizontalPadding: CGFloat = 16
    private let cardCornerRadius: CGFloat = 22
    private let cardPadding: CGFloat = 14
    private let internalSpacing: CGFloat = 10

    var body: some View {
        VStack(alignment: .leading, spacing: internalSpacing) {
            topRow
            mainRow
        }
        .padding(cardPadding)
        .frame(maxWidth: .infinity)
        .background(CashRunwayTheme.surface, in: RoundedRectangle(cornerRadius: cardCornerRadius, style: .continuous))
        .shadow(color: CashRunwayTheme.softShadow, radius: 14, y: 6)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(CashRunwayAccessibilityID.timelineSummaryCard)
    }

    // MARK: - Top row

    // Reference layout: the amount sits on the left, the comparison in the middle
    // column (wrapping as needed), and the vertical legend anchored to the top-right.
    private var topRow: some View {
        HStack(alignment: .top, spacing: internalSpacing) {
            netAmount
                .frame(maxHeight: .infinity, alignment: .leading)
            comparisonView
                .frame(minWidth: 92, maxWidth: .infinity, alignment: .leading)
            legend
        }
    }

    private var netAmount: some View {
        styledNetAmount
            .lineLimit(1)
            .minimumScaleFactor(0.6)
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityIdentifier(CashRunwayAccessibilityID.timelineCashFlowValue)
            // Keep the full, precise amount (kopecks included) for VoiceOver even though
            // the hero displays a rounded figure.
            .accessibilityLabel(presentation.netText)
    }

    // The grouped integer is the hero in a rounded, heavy face; kopecks are dropped here
    // (they stay on the metric cards and feed). The currency symbol recedes as a smaller,
    // muted unit in the same hue. A true minus sign (U+2212) replaces the hyphen.
    private var styledNetAmount: some View {
        let segments = Self.amountSegments(presentation.netText, locale: locale)
        let number = segments.main.replacingOccurrences(of: "-", with: "\u{2212}")
        return (
            Text(number)
                .font(.system(size: 34, weight: .heavy, design: .rounded).monospacedDigit())
                .tracking(-0.5)
                .foregroundStyle(netColor)
            + Text(segments.trailing)
                .font(.system(size: 20, weight: .semibold, design: .rounded))
                .foregroundStyle(netColor.opacity(0.5))
        )
    }

    /// Splits a formatted money string into the integer portion, the decimal fraction
    /// (separator + digits), and the trailing remainder (currency symbol/spacing),
    /// preserving the locale's own grouping and symbol placement.
    private static func amountSegments(_ text: String, locale: Locale) -> (main: String, fraction: String, trailing: String) {
        let separator = locale.decimalSeparator ?? ","
        guard let sepRange = text.range(of: separator, options: .backwards) else {
            return (text, "", "")
        }
        let fractionDigits = text[sepRange.upperBound...].prefix { $0.isNumber }
        guard !fractionDigits.isEmpty else {
            return (text, "", "")
        }
        let main = String(text[..<sepRange.lowerBound])
        let fraction = separator + String(fractionDigits)
        let trailingStart = text.index(sepRange.upperBound, offsetBy: fractionDigits.count)
        let trailing = String(text[trailingStart...])
        return (main, fraction, trailing)
    }

    private var netColor: Color {
        switch presentation.netStyle {
        case .positive: CashRunwayTheme.positive
        case .negative: CashRunwayTheme.negative
        case .zero: CashRunwayTheme.textPrimary
        }
    }

    private var comparisonView: some View {
        Group {
            if let comparison = presentation.comparison {
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 2) {
                        Text(comparison.arrow)
                            .font(.system(size: 15, weight: .bold))
                        if let percentageText = comparison.percentageText {
                            Text(percentageText)
                                .font(.system(size: 15, weight: .bold).monospacedDigit())
                        }
                    }
                    .foregroundStyle(comparisonColor(for: comparison.style))

                    Text(comparison.headline)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(CashRunwayTheme.textSecondary)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .accessibilityIdentifier(CashRunwayAccessibilityID.timelineComparison)
    }

    private func comparisonColor(for style: TimelinePresentation.AmountStyle) -> Color {
        switch style {
        case .positive: CashRunwayTheme.positive
        case .negative: CashRunwayTheme.negative
        case .zero: CashRunwayTheme.textSecondary
        }
    }

    private var legend: some View {
        VStack(alignment: .leading, spacing: 6) {
            legendItem(color: CashRunwayTheme.accent, label: L10n.string("timeline.summary.income"))
            legendItem(color: CashRunwayTheme.negative, label: L10n.string("timeline.summary.expense"))
        }
        .fixedSize()
    }

    private func legendItem(color: Color, label: String) -> some View {
        HStack(spacing: 6) {
            Circle()
                .fill(color)
                .frame(width: 7, height: 7)
            Text(label)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(CashRunwayTheme.textSecondary)
        }
    }

    // MARK: - Main row

    private var mainRow: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .top, spacing: internalSpacing) {
                metricCards
                    .frame(width: 130, alignment: .leading)
                chart
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }

            VStack(alignment: .leading, spacing: internalSpacing) {
                metricCards
                chart
                    .frame(height: 220)
            }
        }
    }

    private var metricCards: some View {
        VStack(alignment: .leading, spacing: internalSpacing) {
            metricCard(
                label: L10n.string("timeline.summary.income"),
                value: presentation.incomeText,
                indicatorColor: CashRunwayTheme.accent,
                iconName: "arrow.down.left",
                identifier: CashRunwayAccessibilityID.timelineIncomeValue
            )
            metricCard(
                label: L10n.string("timeline.summary.expense"),
                value: presentation.expenseText,
                indicatorColor: CashRunwayTheme.negative,
                iconName: "arrow.up.right",
                identifier: CashRunwayAccessibilityID.timelineExpenseValue
            )
        }
    }

    // Tinted card with a full-height rounded accent bar on the leading edge, matching
    // the reference (green for income, red for expenses).
    private func metricCard(label: String, value: String, indicatorColor: Color, iconName: String, identifier: String) -> some View {
        HStack(spacing: 10) {
            RoundedRectangle(cornerRadius: 2.5, style: .continuous)
                .fill(indicatorColor)
                .frame(width: 4)
                .frame(maxHeight: .infinity)
                .padding(.vertical, 8)

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 4) {
                    Text(label)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(CashRunwayTheme.textSecondary)
                    Spacer(minLength: 4)
                    Image(systemName: iconName)
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(indicatorColor)
                        .padding(4)
                        .background(indicatorColor.opacity(0.14), in: Circle())
                }
                Text(value)
                    .font(.system(size: 18, weight: .bold).monospacedDigit())
                    .foregroundStyle(CashRunwayTheme.textPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 8)
            .padding(.trailing, 10)
        }
        .frame(minHeight: 54)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(indicatorColor.opacity(0.10), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(indicatorColor.opacity(0.16), lineWidth: 1)
        )
        .accessibilityIdentifier(identifier)
    }

    private var chart: some View {
        TimelineGroupedBarChart(
            points: presentation.allChartPoints,
            selectedPeriodKey: presentation.selectedPeriodKey,
            period: period,
            currencyCode: presentation.currencyCode,
            locale: locale,
            onSelect: onSelectPeriod
        )
        .frame(minHeight: 132)
    }
}
