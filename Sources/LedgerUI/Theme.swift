import SwiftUI

public enum LedgerTheme {
    public static let background = Color(red: 0.985, green: 0.989, blue: 0.995)
    public static let surface = Color.white
    public static let surfaceMuted = Color(red: 0.962, green: 0.972, blue: 0.982)
    public static let textPrimary = Color(red: 0.176, green: 0.239, blue: 0.337)
    public static let textSecondary = Color(red: 0.455, green: 0.533, blue: 0.608)
    public static let textMuted = Color(red: 0.635, green: 0.694, blue: 0.761)
    public static let accent = Color(red: 0.133, green: 0.785, blue: 0.600)
    public static let accentMuted = Color(red: 0.880, green: 0.973, blue: 0.944)
    public static let accentDark = Color(red: 0.084, green: 0.648, blue: 0.491)
    public static let positive = Color(red: 0.133, green: 0.785, blue: 0.600)
    public static let card = Color.white
    public static let cardMuted = Color(red: 0.948, green: 0.962, blue: 0.977)
    public static let negative = Color(red: 0.968, green: 0.420, blue: 0.395)
    public static let line = Color(red: 0.902, green: 0.924, blue: 0.950)
    public static let pill = Color(red: 0.949, green: 0.964, blue: 0.980)
    public static let chartGrid = Color(red: 0.901, green: 0.921, blue: 0.944)
    public static let composerHeader = Color(red: 0.585, green: 0.886, blue: 0.745)

    public static func categoryColor(_ hex: String?) -> Color {
        guard let hex else { return textSecondary }
        return Color(hex: hex)
    }

    public static func amountColor(_ amountMinor: Int64) -> Color {
        amountMinor < 0 ? negative : positive
    }

    public static func monthAbbreviation(for monthKey: Int) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "MMM"
        return formatter.string(from: DateKeys.startOfMonth(for: monthKey))
    }

    public static func dayHeader(for dayKey: Int) -> String {
        let year = dayKey / 10_000
        let month = (dayKey / 100) % 100
        let day = dayKey % 100
        let date = DateKeys.calendar.date(from: DateComponents(year: year, month: month, day: day)) ?? .now
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "EEEE, d MMM"
        return formatter.string(from: date)
    }
}

extension Color {
    init(hex: String) {
        let hex = hex.replacingOccurrences(of: "#", with: "")
        let scanner = Scanner(string: hex)
        var value: UInt64 = 0
        scanner.scanHexInt64(&value)
        let r = Double((value >> 16) & 0xff) / 255
        let g = Double((value >> 8) & 0xff) / 255
        let b = Double(value & 0xff) / 255
        self.init(red: r, green: g, blue: b)
    }
}

struct CategoryGlyph: View {
    let iconName: String?
    let colorHex: String?
    var size: CGFloat = 50

    var body: some View {
        ZStack {
            Circle()
                .fill(LedgerTheme.categoryColor(colorHex))
            Image(systemName: iconName ?? "circle.fill")
                .font(.system(size: size * 0.34, weight: .semibold))
                .foregroundStyle(.white)
        }
        .frame(width: size, height: size)
    }
}

struct SectionHeader: View {
    let title: String
    let subtitle: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.system(size: 26, weight: .bold, design: .rounded))
                .foregroundStyle(LedgerTheme.textPrimary)
            if let subtitle {
                Text(subtitle)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(LedgerTheme.textMuted)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct ScreenTitle: View {
    let title: String

    var body: some View {
        Text(title)
            .font(.system(size: 32, weight: .bold, design: .rounded))
            .foregroundStyle(LedgerTheme.textPrimary)
            .frame(maxWidth: .infinity, alignment: .center)
    }
}
