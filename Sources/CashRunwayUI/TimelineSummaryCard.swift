import CashRunwayCore
import CashRunwayUIVM
import SwiftUI

struct TimelineSummaryCard: View {
    let presentation: TimelinePresentation
    let period: TimelinePeriod
    let locale: Locale
    let onSelectPeriod: (Int) -> Void
    let onOverview: () -> Void

    private let pageHorizontalPadding: CGFloat = 16
    private let cardCornerRadius: CGFloat = 24
    private let cardPadding: CGFloat = 16
    private let internalSpacing: CGFloat = 12

    var body: some View {
        VStack(alignment: .leading, spacing: internalSpacing) {
            topRow
            mainRow
            spendingOverviewAction
        }
        .padding(cardPadding)
        .frame(maxWidth: .infinity)
        .background(CashRunwayTheme.surface, in: RoundedRectangle(cornerRadius: cardCornerRadius, style: .continuous))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(CashRunwayAccessibilityID.timelineSummaryCard)
    }

    // MARK: - Top row

    private var topRow: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .center, spacing: internalSpacing) {
                netAmount
                comparisonView
                legend
            }

            VStack(alignment: .leading, spacing: internalSpacing) {
                HStack {
                    netAmount
                    Spacer()
                    legend
                }
                comparisonView
            }
        }
    }

    private var netAmount: some View {
        Text(presentation.netText)
            .font(.system(size: 32, weight: .bold).monospacedDigit())
            .foregroundStyle(netColor)
            .lineLimit(1)
            .minimumScaleFactor(0.6)
            .accessibilityIdentifier(CashRunwayAccessibilityID.timelineCashFlowValue)
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
        HStack(spacing: 10) {
            legendItem(color: CashRunwayTheme.accent, label: L10n.string("Income"))
            legendItem(color: CashRunwayTheme.negative, label: L10n.string("Expense"))
        }
    }

    private func legendItem(color: Color, label: String) -> some View {
        HStack(spacing: 5) {
            Circle()
                .fill(color)
                .frame(width: 6, height: 6)
            Text(label)
                .font(.system(size: 11, weight: .medium))
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
                label: L10n.string("Income"),
                value: presentation.incomeText,
                indicatorColor: CashRunwayTheme.accent,
                identifier: CashRunwayAccessibilityID.timelineIncomeValue
            )
            metricCard(
                label: L10n.string("Expense"),
                value: presentation.expenseText,
                indicatorColor: CashRunwayTheme.negative,
                identifier: CashRunwayAccessibilityID.timelineExpenseValue
            )
        }
    }

    private func metricCard(label: String, value: String, indicatorColor: Color, identifier: String) -> some View {
        HStack(alignment: .center, spacing: 8) {
            RoundedRectangle(cornerRadius: 2)
                .fill(indicatorColor)
                .frame(width: 3, height: 38)

            VStack(alignment: .leading, spacing: 2) {
                Text(label)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(CashRunwayTheme.textSecondary)
                Text(value)
                    .font(.system(size: 17, weight: .semibold).monospacedDigit())
                    .foregroundStyle(CashRunwayTheme.textPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
        }
        .frame(minHeight: 56)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(CashRunwayTheme.pill, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .accessibilityIdentifier(identifier)
    }

    private var chart: some View {
        TimelineGroupedBarChart(
            points: presentation.chartPoints,
            selectedPeriodKey: presentation.selectedPeriodKey,
            period: period,
            currencyCode: presentation.currencyCode,
            locale: locale,
            onSelect: onSelectPeriod
        )
        .frame(minHeight: 200)
    }

    // MARK: - Spending Overview

    private var spendingOverviewAction: some View {
        Button {
            onOverview()
        } label: {
            HStack {
                Image(systemName: "chart.pie.fill")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(CashRunwayTheme.textMuted)
                Text(L10n.string("Spending Overview"))
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(CashRunwayTheme.textPrimary)
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(CashRunwayTheme.textMuted)
            }
            .padding(.horizontal, 4)
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(CashRunwayAccessibilityID.overviewOpenButton)
    }
}
