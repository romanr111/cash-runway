import CashRunwayCore
import CashRunwayUIVM
import SwiftUI

struct TimelineGroupedBarChart: View {
    let points: [TimelineBarPoint]
    let selectedPeriodKey: Int
    let period: TimelinePeriod
    let currencyCode: CurrencyCode?
    let locale: Locale
    let onSelect: (Int) -> Void

    private let barWidth: CGFloat = 18
    private let labelReserve: CGFloat = 44
    private let periodLabelReserve: CGFloat = 38
    private let minBarHeight: CGFloat = 4

    var body: some View {
        GeometryReader { geometry in
            let usableHeight = geometry.size.height - labelReserve - periodLabelReserve
            let maxMagnitude = displayedMaxMagnitude
            let scale = maxMagnitude > 0 ? usableHeight / CGFloat(maxMagnitude) : 0

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
            .gesture(
                DragGesture(minimumDistance: 20)
                    .onEnded { value in
                        let shift = dragShift(for: value.translation.width)
                        guard shift != 0, let currentIndex = points.firstIndex(where: { $0.periodKey == selectedPeriodKey }) else { return }
                        let targetIndex = max(0, min(points.count - 1, currentIndex + shift))
                        let targetKey = points[targetIndex].periodKey
                        guard targetKey != selectedPeriodKey else { return }
                        let impact = UIImpactFeedbackGenerator(style: .light)
                        impact.impactOccurred()
                        onSelect(targetKey)
                    }
            )
        }
    }

    private var displayedMaxMagnitude: Int64 {
        let values = points.flatMap { [abs($0.incomeBarMinor), abs($0.expenseBarMinor)] }
        return values.max() ?? 0
    }

    private func dragShift(for translationWidth: CGFloat) -> Int {
        let threshold: CGFloat = 40
        if translationWidth < -threshold { return 1 }
        if translationWidth > threshold { return -1 }
        return 0
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
    private let topLabelReserve: CGFloat = 36
    private let collisionThreshold: CGFloat = 14
    private let collisionStagger: CGFloat = 14

    var body: some View {
        VStack(spacing: 6) {
            barsWithLabels
            periodLabel
        }
    }

    // Each value label is anchored directly above its own bar's top, so bars of
    // different heights naturally separate their labels. When two bars are nearly
    // equal in height, the income label is nudged up so the pair never superimposes.
    private var barsWithLabels: some View {
        HStack(alignment: .bottom, spacing: 4) {
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
                .fill(color.opacity(isSelected ? 1.0 : 0.75))
                .frame(width: barWidth, height: height)

            valueLabel(value: value)
                .offset(y: -(height + labelGap + stagger))
        }
        .frame(width: barWidth, height: maxBarHeight + topLabelReserve, alignment: .bottom)
    }

    private func valueLabel(value: Int64) -> some View {
        Text(value == 0 ? "-" : TimelinePresentation.compactValueText(minorUnits: value, locale: locale))
            .font(.system(size: 10, weight: .semibold).monospacedDigit())
            .foregroundStyle(CashRunwayTheme.textSecondary)
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
            .frame(height: periodLabelHeight)
    }

    private var periodLabelHeight: CGFloat { 34 }
}
