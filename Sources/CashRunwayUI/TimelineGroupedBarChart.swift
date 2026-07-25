import CashRunwayCore
import CashRunwayUIVM
import SwiftUI

/// Shared vertical layout metrics for the grouped bar chart. Kept in one place so the
/// selected-period reference lines (drawn by the parent) stay pixel-aligned with the bar
/// baseline (laid out by `TimelineChartGroup`).
private enum ChartMetrics {
    static let topLabelReserve: CGFloat = 24
    static let periodLabelHeight: CGFloat = 32
    static let barLabelSpacing: CGFloat = 6
}

struct TimelineGroupedBarChart: View {
    let points: [TimelineBarPoint]
    let selectedPeriodKey: Int
    let period: TimelinePeriod
    let currencyCode: CurrencyCode?
    let locale: Locale
    let onSelect: (Int) -> Void

    private let barWidth: CGFloat = 14
    private let labelReserve: CGFloat = 30
    private let periodLabelReserve: CGFloat = 34
    private let minBarHeight: CGFloat = 4

    var body: some View {
        GeometryReader { geometry in
            let usableHeight = geometry.size.height - labelReserve - periodLabelReserve
            let maxMagnitude = displayedMaxMagnitude
            let scale = maxMagnitude > 0 ? usableHeight / CGFloat(maxMagnitude) : 0
            let selected = points.first { $0.periodKey == selectedPeriodKey }
            let baselineY = geometry.size.height - ChartMetrics.periodLabelHeight - ChartMetrics.barLabelSpacing

            ZStack(alignment: .topLeading) {
                // Faint horizontal guides at the selected period's income/expense levels,
                // so every other bar reads as higher/lower than the focused month at a
                // glance. They sit behind the bars and move with the selection.
                if let selected {
                    referenceLine(value: selected.incomeBarMinor, color: CashRunwayTheme.accent, baselineY: baselineY, scale: scale, width: geometry.size.width)
                    referenceLine(value: selected.expenseBarMinor, color: CashRunwayTheme.negative, baselineY: baselineY, scale: scale, width: geometry.size.width)
                }

                HStack(alignment: .bottom, spacing: 0) {
                    ForEach(points) { point in
                        let isSelected = point.periodKey == selectedPeriodKey
                        Button {
                            if point.periodKey != selectedPeriodKey {
                                let impact = UIImpactFeedbackGenerator(style: .light)
                                impact.impactOccurred()
                                onSelect(point.periodKey)
                            }
                        } label: {
                            TimelineChartGroup(
                                point: point,
                                isSelected: isSelected,
                                period: period,
                                locale: locale,
                                barWidth: barWidth,
                                minBarHeight: minBarHeight,
                                scale: scale,
                                maxMagnitude: maxMagnitude
                            )
                            .frame(maxWidth: .infinity)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityElement(children: .ignore)
                        .accessibilityIdentifier(CashRunwayAccessibilityID.timelineChartPoint(point.periodKey))
                        .accessibilityLabel(accessibilityLabel(for: point, isSelected: isSelected))
                        .accessibilityAddTraits(.isButton)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .animation(.spring(response: 0.35, dampingFraction: 0.9), value: selectedPeriodKey)
        }
    }

    // A 1pt full-width guide at the given value's bar height; nothing is drawn for a zero
    // value so no line ever sticks to the baseline.
    @ViewBuilder
    private func referenceLine(value: Int64, color: Color, baselineY: CGFloat, scale: CGFloat, width: CGFloat) -> some View {
        if value > 0 {
            let lineY = baselineY - CGFloat(value) * scale
            Rectangle()
                .fill(color.opacity(0.22))
                .frame(width: width, height: 1)
                .position(x: width / 2, y: lineY)
                .accessibilityHidden(true)
        }
    }

    private var displayedMaxMagnitude: Int64 {
        let values = points.flatMap { [abs($0.incomeBarMinor), abs($0.expenseBarMinor)] }
        return values.max() ?? 0
    }

    private func accessibilityLabel(for point: TimelineBarPoint, isSelected: Bool) -> String {
        let periodName = TimelinePresentation.periodLabel(for: point.periodKey, period: period, locale: locale)
        let resolvedCurrency = currencyCode ?? .uah
        let incomeText = MoneyFormatter.string(from: point.incomeMinor, currencyCode: resolvedCurrency, locale: locale)
        let expenseText = MoneyFormatter.string(from: -point.expenseMinor, currencyCode: resolvedCurrency, locale: locale)
        let selectedText = isSelected ? L10n.string("Selected") : ""
        return [periodName, "\(L10n.string("Income")) \(incomeText)", "\(L10n.string("Expense")) \(expenseText)", selectedText]
            .filter { !$0.isEmpty }
            .joined(separator: ". ")
    }
}

private struct TimelineChartGroup: View {
    let point: TimelineBarPoint
    let isSelected: Bool
    let period: TimelinePeriod
    let locale: Locale
    let barWidth: CGFloat
    let minBarHeight: CGFloat
    let scale: CGFloat
    let maxMagnitude: Int64

    private let labelGap: CGFloat = 4
    private let collisionThreshold: CGFloat = 14
    private let collisionStagger: CGFloat = 14
    private var topLabelReserve: CGFloat { ChartMetrics.topLabelReserve }

    var body: some View {
        VStack(spacing: ChartMetrics.barLabelSpacing) {
            barsWithLabels
            periodLabel
        }
    }

    // Each value label is anchored directly above its own bar's top, so bars of
    // different heights naturally separate their labels. When two bars are nearly
    // equal in height, the income label is nudged up so the pair never superimposes.
    private var barsWithLabels: some View {
        HStack(alignment: .bottom, spacing: 5) {
            barColumn(
                value: point.incomeBarMinor,
                neighbor: point.expenseBarMinor,
                color: CashRunwayTheme.accent,
                staggerWhenClose: true
            )
            barColumn(
                value: point.expenseBarMinor,
                neighbor: point.incomeBarMinor,
                color: CashRunwayTheme.negative,
                staggerWhenClose: false
            )
        }
        .frame(height: maxBarHeight + topLabelReserve, alignment: .bottom)
    }

    private func barColumn(value: Int64, neighbor: Int64, color: Color, staggerWhenClose: Bool) -> some View {
        let height = max(CGFloat(value) * scale, value == 0 ? 0 : minBarHeight)
        let neighborHeight = max(CGFloat(neighbor) * scale, neighbor == 0 ? 0 : minBarHeight)
        let isClose = value > 0 && neighbor > 0 && abs(height - neighborHeight) < collisionThreshold
        let stagger: CGFloat = (staggerWhenClose && isClose) ? collisionStagger : 0
        return ZStack(alignment: .bottom) {
            RoundedRectangle(cornerRadius: 4)
                .fill(color.opacity(isSelected ? 1.0 : 0.7))
                .frame(width: barWidth, height: height)

            // Only the selected period is labelled; every period's exact figure also
            // lives in the Income/Expense cards. This keeps large-value labels from
            // colliding across neighbouring groups while preserving the trend.
            if isSelected {
                valueLabel(value: value)
                    .offset(y: -(height + labelGap + stagger))
            }
        }
        .frame(width: barWidth, height: maxBarHeight + topLabelReserve, alignment: .bottom)
    }

    private func valueLabel(value: Int64) -> some View {
        Text(value == 0 ? "-" : TimelinePresentation.compactValueText(minorUnits: value, locale: locale))
            .font(.system(size: 10, weight: .semibold).monospacedDigit())
            .foregroundStyle(CashRunwayTheme.textPrimary)
            .fixedSize()
    }

    private var maxBarHeight: CGFloat {
        guard maxMagnitude > 0 else { return minBarHeight }
        return CGFloat(maxMagnitude) * scale
    }

    private var periodLabel: some View {
        let label = TimelinePresentation.periodLabel(for: point.periodKey, period: period, locale: locale)
        return Text(label)
            .font(.system(size: isSelected ? 12 : 11, weight: isSelected ? .bold : .medium))
            .foregroundStyle(isSelected ? CashRunwayTheme.textPrimary : CashRunwayTheme.textMuted)
            .multilineTextAlignment(.center)
            .lineLimit(2)
            .frame(height: ChartMetrics.periodLabelHeight)
    }
}
