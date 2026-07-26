import CashRunwayCore
import Foundation

/// Pure UI presentation adapter over the Phase 1 `TimelineSnapshot`.
///
/// Resolves the selected period bar once, formats headline amounts, builds the
/// expense comparison sentence, derives the four-point visible chart window,
/// and exposes accessibility summaries. It never recalculates values from
/// `allBars`; `allBars` is used only for historical chart navigation.
public struct TimelinePresentation: Equatable, Sendable {
    public enum AmountStyle: Equatable, Sendable {
        case positive
        case negative
        case zero
    }

    public struct Comparison: Equatable, Sendable {
        public let percentageText: String?
        public let direction: TimelineComparison.Direction
        public let arrow: String
        public let headline: String
        public let baselineLabel: String
        public let style: AmountStyle
    }

    public let selectedPeriodKey: Int
    /// Authoritative render period, taken from the snapshot (never from a live model
    /// value). Callers must label and select against this so a stale month snapshot
    /// never renders under year labels while an async reload re-keys the data.
    public let period: TimelinePeriod
    public let netText: String
    public let incomeText: String
    public let expenseText: String
    public let netStyle: AmountStyle
    public let comparison: Comparison?
    /// The four-point visible window ending at the selected period.
    public let chartPoints: [TimelineBarPoint]
    /// The full ordered strip of bars (all periods), with the selected snapshot bar
    /// merged in. Drives the horizontal snap-scroll chart, which scrolls over
    /// already-loaded data without a per-step reload.
    public let allChartPoints: [TimelineBarPoint]
    public let accessibilitySummary: String
    public let currencyCode: CurrencyCode?

    /// Creates a deterministic presentation value for the current Timeline screen.
    /// - Parameters:
    ///   - snapshot: Phase 1 selected-period snapshot (single source of truth).
    ///   - allBars: Historical navigation bars. The selected snapshot bar replaces
    ///     the matching historical bar before the visible window is computed.
    ///   - currencyCode: Currency used for amount formatting. `nil` is allowed
    ///     for defensive mixed-currency handling, but production queries should
    ///     normalize to a single currency before reaching the UI.
    ///   - locale: Locale used for compact chart values and comparison baseline labels.
    ///   - now: Anchor date for resolving current/baseline comparison window labels.
    public init(
        snapshot: TimelineSnapshot?,
        allBars: [TimelineBarPoint],
        currencyCode: CurrencyCode?,
        locale: Locale,
        now: Date = Date()
    ) {
        let period = snapshot?.period ?? .month
        let selectedPeriodKey = snapshot.map { Self.anchorPeriodKey(monthKey: $0.anchorMonthKey, period: $0.period) } ?? DateKeys.periodKey(for: now, period: period)

        let selectedBar = snapshot.flatMap { Self.selectedSnapshotBar(in: $0) }
        let heroCashFlowMinor = snapshot?.heroCashFlowMinor ?? 0
        let incomeMinor = selectedBar?.incomeMinor ?? 0
        let expenseMinor = selectedBar?.expenseMinor ?? 0

        self.selectedPeriodKey = selectedPeriodKey
        self.period = period
        self.currencyCode = currencyCode
        self.netStyle = Self.amountStyle(for: heroCashFlowMinor)
        self.netText = Self.formattedMoney(minorUnits: heroCashFlowMinor, currencyCode: currencyCode, locale: locale)
        // Metric cards drop kopecks (whole hryvnia only) - the fraction adds noise at
        // a glance and the hero already reads as a rounded figure.
        self.incomeText = Self.formattedMoney(minorUnits: incomeMinor, currencyCode: currencyCode, locale: locale, fractionDigits: 0)
        self.expenseText = Self.formattedMoney(minorUnits: -Int64(expenseMinor), currencyCode: currencyCode, locale: locale, fractionDigits: 0)
        self.comparison = snapshot?.comparison.map { Self.comparisonPresentation($0, period: period, locale: locale) }
        self.chartPoints = Self.chartPoints(allBars: allBars, selectedBar: selectedBar, selectedPeriodKey: selectedPeriodKey)
        self.allChartPoints = Self.allChartPoints(allBars: allBars, selectedBar: selectedBar)
        self.accessibilitySummary = Self.accessibilitySummary(
            periodLabel: Self.periodLabel(for: selectedPeriodKey, period: period, locale: locale),
            netText: netText,
            incomeText: incomeText,
            expenseText: expenseText,
            comparison: self.comparison
        )
    }

    // MARK: - Selected bar resolution

    private static func selectedSnapshotBar(in snapshot: TimelineSnapshot) -> TimelineBarPoint? {
        let anchorPeriodKey = anchorPeriodKey(monthKey: snapshot.anchorMonthKey, period: snapshot.period)
        return snapshot.bars.first { $0.periodKey == anchorPeriodKey } ?? snapshot.bars.last
    }

    private static func anchorPeriodKey(monthKey: Int, period: TimelinePeriod) -> Int {
        switch period {
        case .month:
            return monthKey
        case .year:
            return monthKey / 100
        }
    }

    // MARK: - Amount formatting

    private static func amountStyle(for minorUnits: Int64) -> AmountStyle {
        if minorUnits > 0 { return .positive }
        if minorUnits < 0 { return .negative }
        return .zero
    }

    private static func formattedMoney(minorUnits: Int64, currencyCode: CurrencyCode?, locale: Locale, fractionDigits: Int = 2) -> String {
        let code = currencyCode ?? .uah
        return MoneyFormatter.string(from: minorUnits, currencyCode: code, locale: locale, fractionDigits: fractionDigits)
    }

    // MARK: - Chart window

    private static func chartPoints(
        allBars: [TimelineBarPoint],
        selectedBar: TimelineBarPoint?,
        selectedPeriodKey: Int,
        maxVisibleCount: Int = 4
    ) -> [TimelineBarPoint] {
        let merged = mergedChartPoints(allBars: allBars, selectedBar: selectedBar)

        guard let selectedIndex = merged.firstIndex(where: { $0.periodKey == selectedPeriodKey }) else {
            return Array(merged.suffix(maxVisibleCount))
        }

        let startIndex = max(0, selectedIndex - (maxVisibleCount - 1))
        return Array(merged[startIndex...selectedIndex])
    }

    /// The full ordered strip (no windowing) with the selected snapshot bar merged in,
    /// so the scrubber can scroll across every period without a per-step reload while
    /// still reflecting the selected period's up-to-date (possibly partial) values.
    private static func allChartPoints(
        allBars: [TimelineBarPoint],
        selectedBar: TimelineBarPoint?
    ) -> [TimelineBarPoint] {
        mergedChartPoints(allBars: allBars, selectedBar: selectedBar)
    }

    private static func mergedChartPoints(
        allBars: [TimelineBarPoint],
        selectedBar: TimelineBarPoint?
    ) -> [TimelineBarPoint] {
        var merged = allBars
        guard let selectedBar else { return merged }

        if let index = merged.firstIndex(where: { $0.periodKey == selectedBar.periodKey }) {
            merged[index] = selectedBar
        } else {
            let insertionIndex = merged.firstIndex { $0.periodKey > selectedBar.periodKey } ?? merged.endIndex
            merged.insert(selectedBar, at: insertionIndex)
        }
        return merged
    }

    /// Locale-aware compact value for chart labels (e.g. `52,8 тис.` / `52.8k`).
    /// Thousand labels at 100k or higher omit their hundreds digit so they fit within
    /// a selected chart column without crowding its edges.
    public static func compactValueText(minorUnits: Int64, locale: Locale) -> String {
        let value = Double(abs(minorUnits)) / 100.0

        let formatter = NumberFormatter()
        formatter.locale = locale
        formatter.numberStyle = .decimal
        formatter.minimumFractionDigits = 0
        formatter.maximumFractionDigits = 1

        if value >= 1_000_000 {
            let scaled = value / 1_000_000
            return "\(formatter.string(from: NSNumber(value: scaled)) ?? "0")\(Self.millionsSuffix(for: locale))"
        }
        if value >= 1_000 {
            let scaled = value / 1_000
            formatter.maximumFractionDigits = scaled >= 100 ? 0 : 1
            return "\(formatter.string(from: NSNumber(value: scaled)) ?? "0")\(Self.thousandsSuffix(for: locale))"
        }
        return formatter.string(from: NSNumber(value: value)) ?? "0"
    }

    private static func thousandsSuffix(for locale: Locale) -> String {
        localizedChartString("timeline.chartValue.thousands", fallback: locale.languageCode == "uk" ? " тис." : "k")
    }

    private static func millionsSuffix(for locale: Locale) -> String {
        localizedChartString("timeline.chartValue.millions", fallback: locale.languageCode == "uk" ? " млн" : "M")
    }

    // MARK: - Period labels

    /// Uppercases only the first character using the given locale, leaving the rest
    /// untouched. Ukrainian month names are lowercase by default; chart axis labels
    /// present them capitalized (`Квіт.`) without affecting mid-sentence uses.
    static func capitalizedFirst(_ value: String, locale: Locale) -> String {
        guard let first = value.first else { return value }
        return String(first).uppercased(with: locale) + value.dropFirst()
    }

    /// Two-line period label for chart groups: month abbreviation and year for month
    /// mode; the year alone for year mode.
    public static func periodLabel(for periodKey: Int, period: TimelinePeriod, locale: Locale) -> String {
        switch period {
        case .month:
            let date = DateKeys.startOfMonth(for: periodKey)
            let formatter = DateFormatter()
            formatter.locale = locale
            formatter.dateFormat = "MMM"
            let month = capitalizedFirst(formatter.string(from: date), locale: locale)
            let year = periodKey / 100
            return "\(month)\n\(year)"
        case .year:
            // A year key is a plain year (e.g. 2024). Defensively decode a
            // month-shaped key (YYYYMM, i.e. >= 10_000) back to its year so a stale
            // month key can never render verbatim as a 6-digit "202407".
            let year = periodKey >= 10_000 ? periodKey / 100 : periodKey
            return "\(year)"
        }
    }

    // MARK: - Comparison

    private static func comparisonPresentation(
        _ comparison: TimelineComparison,
        period: TimelinePeriod,
        locale: Locale
    ) -> Comparison {
        let percentageText = Self.percentageText(for: comparison)
        let baselineLabel = Self.baselineLabel(for: comparison, period: period, locale: locale)
        let (arrow, style) = Self.comparisonStyle(for: comparison.direction)

        let templateKey: String
        switch comparison.direction {
        case .higher:
            templateKey = "timeline.comparison.higher"
        case .lower:
            templateKey = "timeline.comparison.lower"
        case .unchanged:
            templateKey = "timeline.comparison.unchanged"
        case .unavailable:
            templateKey = "timeline.comparison.unavailable"
        }

        let headline: String
        if comparison.direction == .unavailable {
            headline = localizedString(templateKey, fallback: fallbackCopy(for: templateKey))
        } else {
            let format = localizedString(templateKey, fallback: fallbackCopy(for: templateKey))
            headline = String(format: format, baselineLabel)
        }

        return Comparison(
            percentageText: percentageText,
            direction: comparison.direction,
            arrow: arrow,
            headline: headline,
            baselineLabel: baselineLabel,
            style: style
        )
    }

    private static func percentageText(for comparison: TimelineComparison) -> String? {
        guard let percentage = comparison.percentageChange else { return nil }
        let rounded = Int((percentage * 100).rounded())
        guard rounded != 0 else { return nil }
        let sign = rounded > 0 ? "+" : ""
        return "\(sign)\(rounded)%"
    }

    private static func comparisonStyle(for direction: TimelineComparison.Direction) -> (String, AmountStyle) {
        switch direction {
        case .higher:
            return ("↗", .negative)
        case .lower:
            return ("↘", .positive)
        case .unchanged:
            return ("→", .zero)
        case .unavailable:
            return ("", .zero)
        }
    }

    private static func baselineLabel(for comparison: TimelineComparison, period: TimelinePeriod, locale: Locale) -> String {
        let startDate = dayDate(for: comparison.baselineStartDayKey)
        let endDate = dayDate(for: comparison.baselineEndDayKey)

        let formatter = DateIntervalFormatter()
        formatter.locale = locale
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        let interval = formatter.string(from: startDate, to: endDate)

        switch period {
        case .month:
            return interval
        case .year:
            return interval
        }
    }

    private static func dayDate(for dayKey: Int) -> Date {
        let year = dayKey / 10_000
        let month = (dayKey / 100) % 100
        let day = dayKey % 100
        return DateKeys.calendar.date(from: DateComponents(year: year, month: month, day: day)) ?? Date()
    }

    // MARK: - Accessibility

    private static func accessibilitySummary(
        periodLabel: String,
        netText: String,
        incomeText: String,
        expenseText: String,
        comparison: Comparison?
    ) -> String {
        var parts = [String]()
        parts.append("\(localizedString("timeline.accessibility.period", fallback: "Period")) \(periodLabel)")
        parts.append("\(localizedString("timeline.accessibility.net", fallback: "Net cash flow")) \(netText)")
        parts.append("\(localizedString("timeline.accessibility.income", fallback: "Income")) \(incomeText)")
        parts.append("\(localizedString("timeline.accessibility.expense", fallback: "Expenses")) \(expenseText)")
        if let comparison {
            parts.append(comparison.headline)
        }
        return parts.joined(separator: ". ")
    }

    // MARK: - Localization helpers

    private static func localizedString(_ key: String, fallback: String) -> String {
        let value = L10n.string(key)
        return value == key ? fallback : value
    }

    private static func localizedChartString(_ key: String, fallback: String) -> String {
        let value = L10n.string(key)
        return value == key ? fallback : value
    }

    private static func fallbackCopy(for key: String) -> String {
        switch key {
        case "timeline.comparison.higher":
            return "Expenses are higher than %@"
        case "timeline.comparison.lower":
            return "Expenses are lower than %@"
        case "timeline.comparison.unchanged":
            return "Expenses are unchanged from %@"
        case "timeline.comparison.unavailable":
            return "Comparison unavailable"
        default:
            return key
        }
    }
}
