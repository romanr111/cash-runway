import CashRunwayCore
import CashRunwayUIVM
import SwiftUI

/// Shared layout metrics for the grouped bar chart. Kept in one place so the
/// selected-period reference lines (drawn by the parent, fixed) stay pixel-aligned
/// with the bar baseline (laid out by `TimelineChartGroup`, scrolling).
private enum ChartMetrics {
    static let topLabelReserve: CGFloat = 30
    static let periodLabelHeight: CGFloat = 32
    static let barLabelSpacing: CGFloat = 6
    static let barWidth: CGFloat = 14
    static let barSpacing: CGFloat = 5
    static let minBarHeight: CGFloat = 4
    /// Fixed width per period group; also the tap target (>= 44pt with the row height).
    static let groupWidth: CGFloat = 50
    static let groupSpacing: CGFloat = 6
    /// Breathing room from the card edges; also the gap the trailing (current) period
    /// keeps from the right edge.
    static let edgeInset: CGFloat = 12
}

/// A horizontal, right-aligned grouped bar chart for period comparison.
///
/// The current (newest) period sits at the right, with earlier periods filling the
/// space to its left, so several months read side by side for comparison. The strip
/// scrolls freely over already-loaded data (`allChartPoints`) with no per-step reload;
/// tapping a bar selects that period (labels + reference lines + the detail reload).
/// The nested horizontal-in-vertical scroll is resolved natively by SwiftUI, so there
/// is no hand-rolled gesture and no conflict with the enclosing page scroll.
struct TimelineGroupedBarChart: View {
    let points: [TimelineBarPoint]
    let selectedPeriodKey: Int
    let period: TimelinePeriod
    let currencyCode: CurrencyCode?
    let locale: Locale
    let onSelect: (Int) -> Void

    // The selected bar (labels + reference lines). Driven by taps and by external
    // model changes, not by scrolling - scrolling only browses history.
    @State private var selectedKey: Int?
    // The last key handed to `onSelect`, to dedupe against external selection echoes.
    @State private var committedKey: Int?

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(
        points: [TimelineBarPoint],
        selectedPeriodKey: Int,
        period: TimelinePeriod,
        currencyCode: CurrencyCode?,
        locale: Locale,
        onSelect: @escaping (Int) -> Void
    ) {
        self.points = points
        self.selectedPeriodKey = selectedPeriodKey
        self.period = period
        self.currencyCode = currencyCode
        self.locale = locale
        self.onSelect = onSelect
        _selectedKey = State(initialValue: selectedPeriodKey)
        _committedKey = State(initialValue: selectedPeriodKey)
    }

    var body: some View {
        GeometryReader { geometry in
            let width = geometry.size.width
            let height = geometry.size.height
            let usableHeight = max(0, height - ChartMetrics.topLabelReserve - ChartMetrics.periodLabelHeight - ChartMetrics.barLabelSpacing)
            let maxMagnitude = displayedMaxMagnitude
            let scale = maxMagnitude > 0 ? usableHeight / CGFloat(maxMagnitude) : 0
            let baselineY = height - ChartMetrics.periodLabelHeight - ChartMetrics.barLabelSpacing
            let selected = points.first { $0.periodKey == selectedKey }

            ZStack(alignment: .topLeading) {
                // Faint full-width guides at the selected period's income/expense levels,
                // so every other bar reads above/below the focused period at a glance.
                referenceLines(selected: selected, baselineY: baselineY, scale: scale, width: width)

                // The strip of bar groups (right-aligned scroller, or a centered lone bar).
                strip(scale: scale, maxMagnitude: maxMagnitude)
            }
        }
    }

    // MARK: - Strip

    @ViewBuilder
    private func strip(scale: CGFloat, maxMagnitude: Int64) -> some View {
        if points.count > 1 {
            scrollStrip(scale: scale, maxMagnitude: maxMagnitude)
        } else {
            // A single period has nothing to compare against; center it.
            HStack(spacing: ChartMetrics.groupSpacing) {
                ForEach(points) { point in
                    barGroup(point, scale: scale, maxMagnitude: maxMagnitude)
                        .accessibilityElement(children: .ignore)
                        .accessibilityIdentifier(CashRunwayAccessibilityID.timelineChartPoint(point.periodKey))
                        .accessibilityLabel(accessibilityLabel(for: point, isSelected: point.periodKey == selectedKey))
                        .accessibilityAddTraits(point.periodKey == selectedKey ? [.isSelected] : [])
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
            .onAppear { syncSelection(to: selectedPeriodKey) }
            .onChange(of: selectedPeriodKey) { _, newValue in syncSelection(to: newValue) }
        }
    }

    private func scrollStrip(scale: CGFloat, maxMagnitude: Int64) -> some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: ChartMetrics.groupSpacing) {
                    ForEach(points) { point in
                        let isSelected = point.periodKey == selectedKey
                        Button {
                            select(point.periodKey)
                        } label: {
                            barGroup(point, scale: scale, maxMagnitude: maxMagnitude)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .id(point.periodKey)
                        .accessibilityElement(children: .ignore)
                        .accessibilityIdentifier(CashRunwayAccessibilityID.timelineChartPoint(point.periodKey))
                        .accessibilityLabel(accessibilityLabel(for: point, isSelected: isSelected))
                        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
                    }
                }
            }
            .contentMargins(.horizontal, ChartMetrics.edgeInset, for: .scrollContent)
            // Current (newest) period at the right, earlier periods filling to the left.
            .defaultScrollAnchor(.trailing)
            // Keep the selection valid when this branch (re)mounts - e.g. switching from
            // year mode, where a stale `selectedKey` matches no month bar and would leave
            // the strip with nothing emphasised. `onChange` does not fire on mount.
            .onAppear {
                if selectedKey != selectedPeriodKey { syncSelection(to: selectedPeriodKey) }
            }
            .onChange(of: selectedPeriodKey) { _, newValue in
                committedKey = newValue
                // A tap already updated `selectedKey`; only react to a model-driven change
                // (e.g. a period-mode switch), bringing the new current period to the right.
                guard newValue != selectedKey else { return }
                selectedKey = newValue
                scrollToTrailing(newValue, proxy: proxy)
            }
        }
    }

    private func barGroup(_ point: TimelineBarPoint, scale: CGFloat, maxMagnitude: Int64) -> some View {
        let isSelected = point.periodKey == selectedKey
        return TimelineChartGroup(
            point: point,
            isSelected: isSelected,
            period: period,
            locale: locale,
            scale: scale,
            maxMagnitude: maxMagnitude
        )
        .frame(width: ChartMetrics.groupWidth)
        .background {
            if isSelected {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(CashRunwayTheme.pill)
                    .transition(.opacity)
            }
        }
    }

    // MARK: - Selection

    // Tapping a bar selects that period in place (no scroll) and reloads its detail.
    private func select(_ periodKey: Int) {
        guard periodKey != selectedKey else { return }
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        if reduceMotion {
            selectedKey = periodKey
        } else {
            withAnimation(.easeInOut(duration: 0.2)) { selectedKey = periodKey }
        }
        commit(periodKey)
    }

    private func scrollToTrailing(_ key: Int, proxy: ScrollViewProxy) {
        if reduceMotion {
            proxy.scrollTo(key, anchor: .trailing)
        } else {
            withAnimation(.spring(response: 0.35, dampingFraction: 0.9)) {
                proxy.scrollTo(key, anchor: .trailing)
            }
        }
    }

    // Aligns the local selection state to the model's, without a reload (used by the
    // non-scrolling single-bar layout, which has no tap-driven selection to sync it).
    private func syncSelection(to key: Int) {
        selectedKey = key
        committedKey = key
    }

    // Fires the expensive detail reload exactly once per newly-selected period.
    private func commit(_ key: Int) {
        guard key != committedKey else { return }
        committedKey = key
        onSelect(key)
    }

    // MARK: - Reference lines

    private func referenceLines(selected: TimelineBarPoint?, baselineY: CGFloat, scale: CGFloat, width: CGFloat) -> some View {
        ZStack(alignment: .topLeading) {
            if let selected {
                referenceLine(value: selected.incomeBarMinor, color: CashRunwayTheme.accent, baselineY: baselineY, scale: scale, width: width)
                referenceLine(value: selected.expenseBarMinor, color: CashRunwayTheme.negative, baselineY: baselineY, scale: scale, width: width)
            }
        }
        .animation(reduceMotion ? nil : .spring(response: 0.3, dampingFraction: 0.9), value: selectedKey)
    }

    // A 1pt full-width guide at the given value's bar height; nothing is drawn for a
    // zero value so no line ever sticks to the baseline.
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
        // Stable scale over every period: bars keep a fixed height as you scroll, so
        // the fixed reference lines stay meaningful and cross-period comparison holds.
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
    let scale: CGFloat
    let maxMagnitude: Int64

    var body: some View {
        VStack(spacing: ChartMetrics.barLabelSpacing) {
            bars
            periodLabel
        }
    }

    private var bars: some View {
        HStack(alignment: .bottom, spacing: ChartMetrics.barSpacing) {
            bar(value: point.incomeBarMinor, color: CashRunwayTheme.accent)
            bar(value: point.expenseBarMinor, color: CashRunwayTheme.negative)
        }
        .frame(height: maxBarHeight + ChartMetrics.topLabelReserve, alignment: .bottom)
        .overlay(alignment: .top) {
            if isSelected {
                valueLabels
            }
        }
    }

    // Only the selected group is labelled (so labels never collide across neighbours).
    // Income (green) sits above expense (red), stacked and colour-coded at the top, so
    // the two figures never overlap regardless of the bars' relative heights.
    private var valueLabels: some View {
        VStack(spacing: 1) {
            valueLabel(value: point.incomeBarMinor, color: CashRunwayTheme.accent)
            valueLabel(value: point.expenseBarMinor, color: CashRunwayTheme.negative)
        }
    }

    private func bar(value: Int64, color: Color) -> some View {
        let height = max(CGFloat(value) * scale, value == 0 ? 0 : ChartMetrics.minBarHeight)
        return RoundedRectangle(cornerRadius: 4)
            .fill(color.opacity(isSelected ? 1.0 : 0.55))
            .frame(width: ChartMetrics.barWidth, height: height)
    }

    private func valueLabel(value: Int64, color: Color) -> some View {
        Text(value == 0 ? "-" : TimelinePresentation.compactValueText(minorUnits: value, locale: locale))
            .font(.system(size: 10, weight: .semibold).monospacedDigit())
            .foregroundStyle(color)
            .fixedSize()
    }

    private var maxBarHeight: CGFloat {
        guard maxMagnitude > 0 else { return ChartMetrics.minBarHeight }
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
