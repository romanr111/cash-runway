import Foundation

/// A privacy-preserving representation of a title that consists entirely of a
/// masked payment-card identifier.
///
/// Parsing is intentionally conservative: unrelated numeric strings, phone
/// numbers, IBANs, order IDs, and free-form merchant names are left unchanged.
public struct MaskedCardIdentifier: Equatable, Sendable {
    public let leadingDigits: String
    public let trailingDigits: String

    public var displayText: String {
        "\(leadingDigits) •••• \(trailingDigits)"
    }

    /// Search text contains only digits that are also visible in `displayText`.
    public var searchText: String {
        "\(leadingDigits) \(trailingDigits)"
    }

    public var accessibilityLabel: String {
        accessibilityLabel(languageCode: L10n.languageCode)
    }

    public func accessibilityLabel(languageCode: String) -> String {
        if languageCode.lowercased().hasPrefix("uk") {
            return "Картка \(leadingDigits), закінчується на \(trailingDigits)"
        }
        return "Card \(leadingDigits), ending in \(trailingDigits)"
    }

    public static func parse(_ value: String) -> MaskedCardIdentifier? {
        let characters = Array(value.trimmingCharacters(in: .whitespacesAndNewlines))
        guard !characters.isEmpty else { return nil }

        let maskIndices = characters.indices.filter { isMaskCharacter(characters[$0]) }
        guard maskIndices.count >= 4,
              let firstMaskIndex = maskIndices.first,
              let lastMaskIndex = maskIndices.last
        else {
            return nil
        }

        let maskedSection = characters[firstMaskIndex...lastMaskIndex]
        guard maskedSection.allSatisfy({ isMaskCharacter($0) || isSeparator($0) }) else {
            return nil
        }

        guard let rawLeadingDigits = digitGroup(in: characters[..<firstMaskIndex]),
              let trailingDigits = digitGroup(in: characters[characters.index(after: lastMaskIndex)...]),
              (4...8).contains(rawLeadingDigits.count),
              trailingDigits.count == 4
        else {
            return nil
        }

        return MaskedCardIdentifier(
            leadingDigits: String(rawLeadingDigits.prefix(4)),
            trailingDigits: trailingDigits
        )
    }

    public static func privacyPreservingSearchText(for value: String) -> String {
        parse(value)?.searchText ?? value
    }

    private static func digitGroup(in characters: ArraySlice<Character>) -> String? {
        let characters = Array(characters)
        guard let firstDigitIndex = characters.firstIndex(where: isASCIIDigit),
              let lastDigitIndex = characters.lastIndex(where: isASCIIDigit)
        else {
            return nil
        }

        guard characters[..<firstDigitIndex].allSatisfy(isSeparator),
              characters[characters.index(after: lastDigitIndex)...].allSatisfy(isSeparator),
              characters[firstDigitIndex...lastDigitIndex].allSatisfy(isASCIIDigit)
        else {
            return nil
        }

        return String(characters[firstDigitIndex...lastDigitIndex])
    }

    private static func isASCIIDigit(_ character: Character) -> Bool {
        guard character.unicodeScalars.count == 1,
              let scalar = character.unicodeScalars.first
        else {
            return false
        }
        return (48...57).contains(scalar.value)
    }

    private static func isMaskCharacter(_ character: Character) -> Bool {
        character == "*" || character == "•" || character == "x" || character == "X"
    }

    private static func isSeparator(_ character: Character) -> Bool {
        character.isWhitespace
            || character == "-"
            || character == "‐"
            || character == "‑"
            || character == "‒"
            || character == "–"
            || character == "—"
    }
}
