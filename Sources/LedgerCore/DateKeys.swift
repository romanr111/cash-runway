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

    public static func startOfMonth(for monthKey: Int) -> Date {
        let year = monthKey / 100
        let month = monthKey % 100
        return calendar.date(from: DateComponents(year: year, month: month, day: 1)) ?? .now
    }

    public static func label(for monthKey: Int) -> String {
        let date = startOfMonth(for: monthKey)
        return date.formatted(.dateTime.month(.wide).year())
    }
}

