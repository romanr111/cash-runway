import Foundation

// MARK: - Redaction Service

/// Redacts sensitive persistence/bank/security data before it is exposed to an
/// agent-facing DTO or encoded response.
///
/// Hard-blocked fields include: `raw_json`, `counter_iban`, `receipt_id`,
/// `masked_pan`, full account identifiers, bank tokens, database key material,
/// keychain account names, file paths, debug/recovery paths, SQLCipher/database
/// internals, and raw bank payload fields.
public struct AgentRedactionService: Sendable {
    public let maxPreviewLength: Int
    public let forbiddenSubstrings: Set<String>

    public init(
        maxPreviewLength: Int = 120,
        forbiddenSubstrings: Set<String> = [
            "raw_json",
            "counter_iban",
            "receipt_id",
            "masked_pan",
            "keychain",
            "file://",
            ".sqlite",
            ".sqlite-wal",
            ".sqlite-shm",
            "recovery_key",
            "cipher_page_size",
            "kdf_iter"
        ]
    ) {
        self.maxPreviewLength = max(10, maxPreviewLength)
        self.forbiddenSubstrings = forbiddenSubstrings
    }

    // MARK: - Top-level checks

    /// Returns `true` if the encoded JSON representation contains any hard-blocked
    /// substring. This is intentionally conservative: if a forbidden literal appears
    /// anywhere in the encoded output, the response must not leave the service.
    public func containsBlockedContent(_ data: Data) -> Bool {
        guard let string = String(data: data, encoding: .utf8) else {
            return true
        }
        let lowercased = string.lowercased()
        for forbidden in forbiddenSubstrings {
            if lowercased.contains(forbidden) {
                return true
            }
        }
        return false
    }

    // MARK: - Field redaction

    /// Produces a merchant preview from an optional merchant string.
    public func merchantPreview(_ merchant: String?, include: Bool) -> String? {
        guard include else { return nil }
        guard let merchant, !merchant.isEmpty else { return nil }
        let trimmed = String(merchant.prefix(maxPreviewLength))
        return redactAccountLikePatterns(trimmed)
    }

    /// Produces a note preview from an optional note string.
    public func notePreview(_ note: String?, include: Bool) -> String? {
        guard include else { return nil }
        guard let note, !note.isEmpty else { return nil }
        let trimmed = String(note.prefix(maxPreviewLength))
        return redactAccountLikePatterns(trimmed)
    }

    /// Filters a label list according to scope.
    public func labels(_ labels: [String], include: Bool) -> [String] {
        guard include else { return [] }
        return labels
            .map { String($0.prefix(maxPreviewLength)) }
            .map(redactAccountLikePatterns)
    }

    /// Redacts account/IBAN/card-like patterns from free-form text.
    ///
    /// Uses deterministic string scanning (no `NSRegularExpression`) so it is
    /// safe to call from Swift concurrency contexts and cannot backtrack.
    /// Patterns covered:
    /// - 16–19 digit card numbers (with optional spaces/hyphens every 4 digits)
    /// - IBANs: 2 letters + 2 digits + 4–30 alphanumeric characters
    /// - 8–34 digit account numbers
    public func redactAccountLikePatterns(_ text: String) -> String {
        var result = text
        result = redactIBANs(in: result)
        result = redactCards(in: result)
        result = redactAccountNumbers(in: result)
        return result
    }

    private func redactIBANs(in text: String) -> String {
        var result = ""
        let chars = Array(text)
        var index = 0
        while index < chars.count {
            if isIBANStart(chars, index) {
                var length = 4 // country + check digits
                index += 4
                while index < chars.count, isIBANBodyChar(chars[index]), length < 34 {
                    index += 1
                    length += 1
                }
                result += "[REDACTED_IBAN]"
            } else {
                result.append(chars[index])
                index += 1
            }
        }
        return result
    }

    private func isIBANStart(_ chars: [Character], _ index: Int) -> Bool {
        guard index + 3 < chars.count else { return false }
        return chars[index].isLetter && chars[index + 1].isLetter
            && chars[index + 2].isNumber && chars[index + 3].isNumber
    }

    private func isIBANBodyChar(_ char: Character) -> Bool {
        char.isLetter || char.isNumber
    }

    private func redactCards(in text: String) -> String {
        var result = ""
        let chars = Array(text)
        var index = 0
        while index < chars.count {
            if chars[index].isNumber {
                let start = index
                var digits = 0
                var groups = 0
                while index < chars.count {
                    let char = chars[index]
                    if char.isNumber {
                        digits += 1
                        index += 1
                    } else if [" ", "-"].contains(char), digits > 0, digits % 4 == 0 {
                        index += 1
                    } else {
                        break
                    }
                    if digits == 4 {
                        groups = 1
                    } else if digits == 8 || digits == 12 || digits == 16 {
                        groups += 1
                    }
                }
                if (16...19).contains(digits), groups >= 3 {
                    result += "[REDACTED_CARD]"
                } else {
                    result.append(contentsOf: chars[start..<index])
                }
            } else {
                result.append(chars[index])
                index += 1
            }
        }
        return result
    }

    private func redactAccountNumbers(in text: String) -> String {
        var result = ""
        let chars = Array(text)
        var index = 0
        while index < chars.count {
            if chars[index].isNumber {
                let start = index
                var digits = 0
                while index < chars.count, chars[index].isNumber {
                    digits += 1
                    index += 1
                }
                if (8...34).contains(digits) {
                    result += "[REDACTED_ACCOUNT]"
                } else {
                    result.append(contentsOf: chars[start..<index])
                }
            } else {
                result.append(chars[index])
                index += 1
            }
        }
        return result
    }
}
