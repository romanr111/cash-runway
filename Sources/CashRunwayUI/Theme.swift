import SwiftUI
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

public enum CashRunwayTheme {
    public static let background = Color(light: "F8FAFC", dark: "11161B")
    public static let surface = Color(light: "FFFFFF", dark: "1B2229")
    public static let surfaceMuted = Color(light: "F1F6F8", dark: "232C34")
    public static let textPrimary = Color(light: "2D3D56", dark: "EEF5F6")
    public static let textSecondary = Color(light: "74889B", dark: "A8B5BE")
    public static let textMuted = Color(light: "A2B1C2", dark: "6F7E88")
    public static let accent = Color(light: "21C596", dark: "33D0A6")
    public static let accentMuted = Color(light: "E1F8F1", dark: "143A33")
    public static let accentDark = Color(light: "159E78", dark: "6FE3C1")
    public static let positive = Color(light: "21C596", dark: "33D0A6")
    public static let card = surface
    public static let cardMuted = Color(light: "EDF4F8", dark: "232C34")
    public static let negative = Color(light: "F35E63", dark: "FF7D83")
    public static let warning = Color(light: "E99A31", dark: "F5B75D")
    public static let line = Color(light: "DDE7EF", dark: "34404A")
    public static let pill = Color(light: "F1F6F8", dark: "26313A")
    public static let chartGrid = Color(light: "D7E3EB", dark: "34404A")
    public static let composerHeader = Color(light: "8EE4BF", dark: "19765E")
    public static let dataTint = Color(light: "2AAAD2", dark: "62C8E6")
    public static let manageTint = Color(light: "5CCDC8", dark: "7CE1DC")
    public static let safetyTint = Color(light: "E85D8E", dark: "F282AA")

    public static let spaceXS: CGFloat = 4
    public static let spaceS: CGFloat = 8
    public static let spaceM: CGFloat = 16
    public static let spaceL: CGFloat = 24
    public static let spaceXL: CGFloat = 32

    public static let radiusS: CGFloat = 12
    public static let radiusM: CGFloat = 18
    public static let radiusL: CGFloat = 24

    public static let displayFont = Font.system(size: 32, weight: .bold, design: .rounded)
    public static let headingFont = Font.system(size: 22, weight: .bold, design: .rounded)
    public static let subheadingFont = Font.system(size: 17, weight: .semibold)
    public static let bodyFont = Font.system(size: 15, weight: .regular)
    public static let captionFont = Font.system(size: 13, weight: .medium)

    public static let softShadow = Color.black.opacity(0.05)

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

    public static func monthFullLabel(for monthKey: Int) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale.current
        formatter.dateFormat = "MMMM yyyy"
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
        let hex = hex.replacingOccurrences(of: "#", with: "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard hex.count == 6 else {
            self.init(red: 0.455, green: 0.533, blue: 0.608)
            return
        }
        let scanner = Scanner(string: hex)
        var value: UInt64 = 0
        guard scanner.scanHexInt64(&value) else {
            self.init(red: 0.455, green: 0.533, blue: 0.608)
            return
        }
        let redComponent = Double((value >> 16) & 0xff) / 255
        let greenComponent = Double((value >> 8) & 0xff) / 255
        let blueComponent = Double(value & 0xff) / 255
        self.init(red: redComponent, green: greenComponent, blue: blueComponent)
    }

    init(light lightHex: String, dark darkHex: String) {
        #if canImport(UIKit)
        self.init(uiColor: UIColor { traits in
            traits.userInterfaceStyle == .dark ? UIColor(hex: darkHex) : UIColor(hex: lightHex)
        })
        #elseif canImport(AppKit)
        self.init(nsColor: NSColor(name: nil) { appearance in
            let bestMatch = appearance.bestMatch(from: [.darkAqua, .aqua])
            return bestMatch == .darkAqua ? NSColor(hex: darkHex) : NSColor(hex: lightHex)
        })
        #else
        self.init(hex: lightHex)
        #endif
    }
}

#if canImport(UIKit)
private extension UIColor {
    convenience init(hex: String) {
        let hex = hex.replacingOccurrences(of: "#", with: "").trimmingCharacters(in: .whitespacesAndNewlines)
        let scanner = Scanner(string: hex)
        var value: UInt64 = 0
        scanner.scanHexInt64(&value)
        self.init(
            red: CGFloat((value >> 16) & 0xff) / 255,
            green: CGFloat((value >> 8) & 0xff) / 255,
            blue: CGFloat(value & 0xff) / 255,
            alpha: 1
        )
    }
}
#elseif canImport(AppKit)
private extension NSColor {
    convenience init(hex: String) {
        let hex = hex.replacingOccurrences(of: "#", with: "").trimmingCharacters(in: .whitespacesAndNewlines)
        let scanner = Scanner(string: hex)
        var value: UInt64 = 0
        scanner.scanHexInt64(&value)
        self.init(
            calibratedRed: CGFloat((value >> 16) & 0xff) / 255,
            green: CGFloat((value >> 8) & 0xff) / 255,
            blue: CGFloat(value & 0xff) / 255,
            alpha: 1
        )
    }
}
#endif

struct CategoryGlyph: View {
    let iconName: String?
    let colorHex: String?
    var size: CGFloat = 50

    var body: some View {
        let baseColor = CashRunwayTheme.categoryColor(colorHex)
        ZStack {
            Circle()
                .fill(baseColor.opacity(0.16))
            Circle()
                .stroke(baseColor.opacity(0.20), lineWidth: 1)
            Image(systemName: CategoryAppearanceCatalog.renderableIconName(iconName))
                .font(.system(size: size * 0.38, weight: .semibold))
                .foregroundStyle(baseColor)
        }
        .frame(width: size, height: size)
    }
}

struct CategoryAppearanceChoice: Identifiable, Hashable {
    let id: String
    let name: String
    let iconName: String?
    let colorHex: String

    init(name: String, iconName: String? = nil, colorHex: String) {
        self.id = iconName.map { "\(name)-\($0)-\(colorHex)" } ?? "\(name)-\(colorHex)"
        self.name = name
        self.iconName = iconName
        self.colorHex = colorHex
    }
}

enum CategoryAppearanceCatalog {
    static let defaultIcon = "ellipsis.circle.fill"
    static let defaultColor = "#21C596"

    static let colors: [CategoryAppearanceChoice] = [
        .init(name: "Mint", colorHex: "#21C596"),
        .init(name: "Aqua", colorHex: "#5CCDC8"),
        .init(name: "Sky", colorHex: "#2AAAD2"),
        .init(name: "Blue", colorHex: "#4D86C6"),
        .init(name: "Lime", colorHex: "#88C95A"),
        .init(name: "Gold", colorHex: "#F2C230"),
        .init(name: "Ochre", colorHex: "#B58B4A"),
        .init(name: "Orange", colorHex: "#E58A33"),
        .init(name: "Coral", colorHex: "#F35E63"),
        .init(name: "Rose", colorHex: "#E85D8E"),
        .init(name: "Violet", colorHex: "#7B61D8"),
        .init(name: "Slate", colorHex: "#60788A")
    ]

    static let icons: [CategoryAppearanceChoice] = [
        .init(name: "Other", iconName: "ellipsis.circle.fill", colorHex: defaultColor),
        .init(name: "Groceries", iconName: "basket.fill", colorHex: "#21C596"),
        .init(name: "Restaurant", iconName: "fork.knife", colorHex: "#5CCDC8"),
        .init(name: "Coffee", iconName: "cup.and.saucer.fill", colorHex: "#5CCDC8"),
        .init(name: "Transport", iconName: "tram.fill", colorHex: "#F2C230"),
        .init(name: "Travel", iconName: "airplane", colorHex: "#E85D8E"),
        .init(name: "Bills", iconName: "doc.text.fill", colorHex: "#21C596"),
        .init(name: "Home", iconName: "house.fill", colorHex: "#E58A33"),
        .init(name: "Healthcare", iconName: "cross.case.fill", colorHex: "#F35E63"),
        .init(name: "Shopping", iconName: "bag.fill", colorHex: "#5CCDC8"),
        .init(name: "Education", iconName: "book.closed.fill", colorHex: "#4D86C6"),
        .init(name: "Family", iconName: "person.2.fill", colorHex: "#F35E63"),
        .init(name: "Gifts", iconName: "gift.fill", colorHex: "#F35E63"),
        .init(name: "Salary", iconName: "briefcase.fill", colorHex: "#2AAAD2"),
        .init(name: "Income", iconName: "plus.circle.fill", colorHex: "#88C95A"),
        .init(name: "Wallet", iconName: "wallet.pass.fill", colorHex: "#60788A"),
        .init(name: "Card", iconName: "creditcard.fill", colorHex: "#21C596")
    ]

    static func normalizedIconName(_ iconName: String?) -> String {
        renderableIconName(iconName)
    }

    static func normalizedColorHex(_ colorHex: String?) -> String {
        let trimmed = colorHex?.trimmingCharacters(in: .whitespacesAndNewlines).uppercased() ?? ""
        guard !trimmed.isEmpty else { return defaultColor }
        return trimmed.hasPrefix("#") ? trimmed : "#\(trimmed)"
    }

    static func renderableIconName(_ iconName: String?) -> String {
        let candidate = iconName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !candidate.isEmpty else { return defaultIcon }
        #if canImport(UIKit)
        return UIImage(systemName: candidate) == nil ? defaultIcon : candidate
        #elseif canImport(AppKit)
        return NSImage(systemSymbolName: candidate, accessibilityDescription: nil) == nil ? defaultIcon : candidate
        #else
        return candidate
        #endif
    }
}

struct CashRunwaySwatch: View {
    let colorHex: String
    let isSelected: Bool

    var body: some View {
        Circle()
            .fill(Color(hex: colorHex))
            .frame(width: 34, height: 34)
            .overlay {
                if isSelected {
                    Image(systemName: "checkmark")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(.white)
                }
            }
            .overlay(Circle().stroke(CashRunwayTheme.line, lineWidth: 1))
            .frame(width: 46, height: 46)
            .contentShape(Circle())
    }
}

struct CashRunwaySurface<Content: View>: View {
    var cornerRadius: CGFloat = CashRunwayTheme.radiusL
    @ViewBuilder let content: Content

    var body: some View {
        content
            .padding(CashRunwayTheme.spaceM)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(CashRunwayTheme.surface, in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous).stroke(CashRunwayTheme.line, lineWidth: 1))
            .shadow(color: CashRunwayTheme.softShadow, radius: 12, y: 4)
    }
}

struct OperationRow: View {
    let icon: String
    let tint: Color
    let title: String
    let subtitle: String
    var trailing: String?
    var showsChevron = true

    var body: some View {
        HStack(spacing: 14) {
            ZStack {
                Circle()
                    .fill(tint.opacity(0.14))
                Image(systemName: icon)
                    .font(.system(size: 19, weight: .semibold))
                    .foregroundStyle(tint)
            }
            .frame(width: 46, height: 46)

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(CashRunwayTheme.subheadingFont)
                    .foregroundStyle(CashRunwayTheme.textPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                Text(subtitle)
                    .font(CashRunwayTheme.captionFont)
                    .foregroundStyle(CashRunwayTheme.textSecondary)
                    .lineLimit(2)
            }

            Spacer(minLength: 12)

            if let trailing {
                Text(trailing)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(CashRunwayTheme.textSecondary)
                    .lineLimit(1)
            }
            if showsChevron {
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(CashRunwayTheme.textMuted)
            }
        }
        .frame(minHeight: 58)
        .contentShape(Rectangle())
    }
}

extension View {
    func ledgerSurface(cornerRadius: CGFloat = CashRunwayTheme.radiusL) -> some View {
        padding(CashRunwayTheme.spaceM)
            .background(CashRunwayTheme.surface, in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous).stroke(CashRunwayTheme.line, lineWidth: 1))
    }
}

struct SectionHeader: View {
    let title: String
    let subtitle: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.system(size: 26, weight: .bold, design: .rounded))
                .foregroundStyle(CashRunwayTheme.textPrimary)
            if let subtitle {
                Text(subtitle)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(CashRunwayTheme.textMuted)
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
            .foregroundStyle(CashRunwayTheme.textPrimary)
            .frame(maxWidth: .infinity, alignment: .center)
    }
}
