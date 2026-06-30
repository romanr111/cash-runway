import Foundation
import Testing
@testable import CashRunwayCore

@Suite("Agent Redaction Service Unit")
struct AgentRedactionServiceUnitTests {

    @Test func redactsIBANAndCard() {
        let service = AgentRedactionService()
        let text = "Payment to UA12345678901234567890123456 from 4111111111111111"
        let result = service.redactAccountLikePatterns(text)
        #expect(result.contains("[REDACTED_IBAN]"))
        #expect(result.contains("[REDACTED_CARD]"))
    }

    @Test func blocksForbiddenLiteral() {
        let service = AgentRedactionService()
        let data = Data("merchant raw_json".utf8)
        #expect(service.containsBlockedContent(data) == true)
    }

    @Test func merchantPreviewRedactsBeforeReturning() {
        let service = AgentRedactionService()
        let preview = service.merchantPreview("Coffee 4111111111111111", include: true)
        #expect(preview?.contains("[REDACTED_CARD]") == true)
    }
}
