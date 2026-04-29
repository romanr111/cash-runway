import Foundation

public enum DateKeys {
    public static let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = Locale(identifier: "uk_UA")
        calendar.timeZone = .current
        return calendar
    }()

    public static func dayKey(for date: Date) -> Int {
        let components = calendar.dateComponents([.year, .month, .day], from: date)
        return (components.year ?? 0) * 10_000 + (components.month ?? 0) * 100 + (components.day ?? 0)
    }

    public static func monthKey(for date: Date) -> Int {
        let components = calendar.dateComponents([.year, .month], from: date)
        return (components.year ?? 0) * 100 + (components.month ?? 0)
    }

    public static func weekKey(for date: Date) -> Int {
        let components = calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: date)
        let year = components.yearForWeekOfYear ?? 0
        let week = components.weekOfYear ?? 0
        return year * 1_000 + week
    }

    public static func yearKey(for date: Date) -> Int {
        let components = calendar.dateComponents([.year], from: date)
        return components.year ?? 0
    }

    public static func periodKey(for date: Date, period: TimelinePeriod) -> Int {
        switch period {
        case .day:
            return dayKey(for: date)
        case .week:
            return weekKey(for: date)
        case .month:
            return monthKey(for: date)
        case .year:
            return yearKey(for: date)
        }
    }

    public static func startOfMonth(for monthKey: Int) -> Date {
        let year = monthKey / 100
        let month = monthKey % 100
        return calendar.date(from: DateComponents(year: year, month: month, day: 1)) ?? .now
    }

    public static func label(for monthKey: Int) -> String {
        let date = startOfMonth(for: monthKey)
        return date.formatted(.dateTime.month(.wide).year())
    }

    public static func startOfWeek(for weekKey: Int) -> Date {
        let year = weekKey / 1_000
        let week = weekKey % 1_000
        var components = DateComponents(year: year, weekday: calendar.firstWeekday)
        components.weekOfYear = week
        return calendar.date(from: components) ?? .now
    }

    public static func weekDateRange(for weekKey: Int) -> (start: Date, end: Date) {
        let start = startOfWeek(for: weekKey)
        let end = calendar.date(byAdding: .day, value: 6, to: start) ?? start
        return (start, end)
    }

    public static func periodLabel(periodKey: Int, period: TimelinePeriod) -> String {
        switch period {
        case .day:
            let year = periodKey / 10_000
            let month = (periodKey / 100) % 100
            let day = periodKey % 100
            let date = calendar.date(from: DateComponents(year: year, month: month, day: day)) ?? .now
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.dateFormat = "EEEE, d MMM"
            return formatter.string(from: date)

        case .week:
            let range = weekDateRange(for: periodKey)
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.dateFormat = "d MMM"
            let start = formatter.string(from: range.start)
            let end = formatter.string(from: range.end)
            return "\(start) – \(end)"

        case .month:
            let date = startOfMonth(for: periodKey)
            return date.formatted(.dateTime.month(.wide).year())

        case .year:
            return "\(periodKey)"
        }
    }
}
