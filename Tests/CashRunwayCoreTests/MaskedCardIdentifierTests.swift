import Testing
@testable import CashRunwayCore

struct MaskedCardIdentifierTests {
    @Test func normalizesSupportedMaskVariants() throws {
        let variants = [
            "537552****6627",
            "5375 **** 6627",
            "5375••••6627",
            "5375-****-6627",
            "5375 xxxx 6627",
            "5375-XXXX-6627",
            "  537552 •••• 6627  ",
        ]

        for value in variants {
            let identifier = try #require(MaskedCardIdentifier.parse(value))
            #expect(identifier.leadingDigits == "5375")
            #expect(identifier.trailingDigits == "6627")
            #expect(identifier.displayText == "5375 •••• 6627")
            #expect(identifier.searchText == "5375 6627")
        }
    }

    @Test func normalizedDisplayValueIsIdempotent() throws {
        let identifier = try #require(MaskedCardIdentifier.parse("5375 •••• 6627"))
        let reparsed = try #require(MaskedCardIdentifier.parse(identifier.displayText))

        #expect(reparsed == identifier)
    }

    @Test func rejectsUnrelatedNumericAndFreeFormStrings() {
        let values = [
            "5375526627",
            "+380 67 123 4567",
            "UA123456789012345678901234567",
            "Order 5375****6627",
            "Receipt 537552-6627",
            "1234-5678-9012-3456",
            "5375/****/6627",
            "merchant5375****6627",
        ]

        for value in values {
            #expect(MaskedCardIdentifier.parse(value) == nil)
            #expect(MaskedCardIdentifier.privacyPreservingSearchText(for: value) == value)
        }
    }

    @Test func rejectsPartialOrAmbiguousMaskedValues() {
        let values = [
            "537****6627",
            "5375***6627",
            "5375****627",
            "5375****12345",
            "123456789****6627",
            "****6627",
            "5375****",
            "",
        ]

        for value in values {
            #expect(MaskedCardIdentifier.parse(value) == nil)
        }
    }

    @Test func searchTextContainsOnlyVisibleDigits() throws {
        let identifier = try #require(MaskedCardIdentifier.parse("537552****6627"))

        #expect(identifier.searchText == "5375 6627")
        #expect(!identifier.searchText.contains("537552"))
        #expect(MaskedCardIdentifier.privacyPreservingSearchText(for: "537552****6627") == "5375 6627")
    }

    @Test func accessibilityLabelsDoNotExposeHiddenDigits() throws {
        let identifier = try #require(MaskedCardIdentifier.parse("537552****6627"))

        let english = identifier.accessibilityLabel(languageCode: "en")
        let ukrainian = identifier.accessibilityLabel(languageCode: "uk")

        #expect(english == "Card 5375, ending in 6627")
        #expect(ukrainian == "Картка 5375, закінчується на 6627")
        #expect(!english.contains("537552"))
        #expect(!ukrainian.contains("537552"))
    }
}
