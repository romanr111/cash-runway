import Foundation
import Testing
@testable import CashRunwayCore

@Suite
struct ReportIssueTests {
    @Test func payloadEncodesBackendContract() throws {
        let payload = ReportIssuePayload(
            category: .bug,
            idempotencyKey: "attempt-1",
            title: "CSV import crashes",
            description: "The app crashes after selecting a CSV file.",
            screen: "CSVImportView",
            diagnostics: ReportIssueDiagnostics(
                appVersion: "1.0.0",
                buildNumber: "42",
                iosVersion: "18.7",
                deviceModel: "iPhone15,4",
                locale: "uk-UA",
                timezone: "Europe/Uzhgorod",
                installHash: "sha256:abcdef"
            )
        )

        let data = try JSONEncoder().encode(payload)
        let json = try #require(String(data: data, encoding: .utf8))

        #expect(json.contains(#""category":"bug""#))
        #expect(json.contains(#""idempotencyKey":"attempt-1""#))
        #expect(json.contains(#""title":"CSV import crashes""#))
        #expect(json.contains(#""installHash":"sha256:abcdef""#))
    }

    @Test func payloadDoesNotEncodeForbiddenFinancialFields() throws {
        let payload = validPayload(idempotencyKey: "attempt-1")
        let data = try JSONEncoder().encode(payload)
        let json = try #require(String(data: data, encoding: .utf8))

        #expect(!json.contains("transactions"))
        #expect(!json.contains("balance"))
        #expect(!json.contains("monobankToken"))
        #expect(!json.contains("logs"))
        #expect(!json.contains("csv"))
        #expect(!json.contains("screenshot"))
    }

    @Test func draftValidationRejectsInvalidTitle() {
        var draft = ReportIssueDraft()
        draft.title = "Bug"
        draft.description = "The app crashes after selecting a CSV file."

        #expect(throws: ReportIssueValidationError.invalid("Title must be 5-120 characters.")) {
            _ = try draft.validatedPayload(diagnostics: nil, idempotencyKey: "attempt-1")
        }
    }

    @Test func draftValidationRejectsInvalidDescription() {
        var draft = ReportIssueDraft()
        draft.title = "CSV import crashes"
        draft.description = "Too short"

        #expect(throws: ReportIssueValidationError.invalid("Description must be 20-4000 characters.")) {
            _ = try draft.validatedPayload(diagnostics: nil, idempotencyKey: "attempt-1")
        }
    }

    @Test func draftValidationAllowsSafeFinanceFeatureWording() throws {
        let balanceDraft = ReportIssueDraft(
            title: "Balance display is wrong",
            description: "The balance display is wrong after opening the wallet screen, but I am not including any private values."
        )
        let monobankDraft = ReportIssueDraft(
            title: "Monobank token screen fails",
            description: "The Monobank token screen does not show the validation error after I tap continue."
        )

        #expect(try balanceDraft.validatedPayload(diagnostics: nil, idempotencyKey: "attempt-1").title == "Balance display is wrong")
        #expect(try monobankDraft.validatedPayload(diagnostics: nil, idempotencyKey: "attempt-1").title == "Monobank token screen fails")
    }

    @Test func draftValidationRejectsPastedFinancialValues() {
        let balanceDraft = ReportIssueDraft(
            title: "Balance display is wrong",
            description: "My account balance is 120000 UAH and the display is wrong."
        )
        let tokenDraft = ReportIssueDraft(
            title: "Monobank token screen fails",
            description: "My Monobank token is abcdef1234567890abcdef1234567890 and validation fails."
        )

        #expect(throws: ReportIssueValidationError.invalid("Do not include account numbers, balances, transaction details, Monobank tokens, CSV exports, database files, screenshots, or logs.")) {
            _ = try balanceDraft.validatedPayload(diagnostics: nil, idempotencyKey: "attempt-1")
        }
        #expect(throws: ReportIssueValidationError.invalid("Do not include account numbers, balances, transaction details, Monobank tokens, CSV exports, database files, screenshots, or logs.")) {
            _ = try tokenDraft.validatedPayload(diagnostics: nil, idempotencyKey: "attempt-1")
        }
    }

    @Test func categoryMapsToBackendString() throws {
        #expect(ReportIssueCategory.bug.rawValue == "bug")
        #expect(ReportIssueCategory.improvement.rawValue == "improvement")
    }

    @Test func diagnosticsToggleControlsPayloadDiagnostics() throws {
        let diagnostics = ReportIssueDiagnostics(
            appVersion: "1.0.0",
            buildNumber: "42",
            iosVersion: "18.7",
            deviceModel: "iPhone15,4",
            locale: "uk-UA",
            timezone: "Europe/Uzhgorod",
            installHash: "sha256:abcdef"
        )
        var draft = ReportIssueDraft(title: "CSV import crashes", description: "The app crashes after selecting a CSV file.")

        draft.includeDiagnostics = true
        #expect(try draft.validatedPayload(diagnostics: diagnostics, idempotencyKey: "attempt-1").appVersion == "1.0.0")

        draft.includeDiagnostics = false
        #expect(try draft.validatedPayload(diagnostics: diagnostics, idempotencyKey: "attempt-1").appVersion == nil)
    }

    @Test func installHashIsStable() {
        let provider = AnonymousInstallIDProvider(
            loadID: { "install-id" },
            saveID: { _ in }
        )

        #expect(provider.installHash() == provider.installHash())
        #expect(provider.installHash().hasPrefix("sha256:"))
    }

    @Test func serviceHandlesCreatedResponse() async throws {
        let service = ReportIssueService(
            endpointURL: URL(string: "https://reports.example.test/api/reports")!,
            clientSecret: "secret",
            transport: MockReportIssueTransport(statusCode: 201, body: #"{"status":"created","issueNumber":123}"#)
        )

        let response = try await service.submit(validPayload(idempotencyKey: "attempt-1"))

        #expect(response.status == "created")
        #expect(response.issueNumber == 123)
    }

    @Test func serviceHandlesErrorResponses() async {
        let payload = validPayload(idempotencyKey: "attempt-1")

        await #expect(throws: ReportIssueServiceError.validation("Invalid report.")) {
            _ = try await ReportIssueService.test(statusCode: 400, body: #"{"error":"Invalid report."}"#).submit(payload)
        }
        await #expect(throws: ReportIssueServiceError.rateLimited) {
            _ = try await ReportIssueService.test(statusCode: 429, body: #"{"error":"Too many reports."}"#).submit(payload)
        }
        await #expect(throws: ReportIssueServiceError.server(502)) {
            _ = try await ReportIssueService.test(statusCode: 502, body: #"{"error":"Could not create GitHub issue."}"#).submit(payload)
        }
    }

    private func validPayload(idempotencyKey: String = "attempt-1") -> ReportIssuePayload {
        ReportIssuePayload(
            category: .bug,
            idempotencyKey: idempotencyKey,
            title: "CSV import crashes",
            description: "The app crashes after selecting a CSV file.",
            screen: "CSVImportView",
            diagnostics: nil
        )
    }
}

private struct MockReportIssueTransport: ReportIssueTransport {
    let statusCode: Int
    let body: String

    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        #expect(request.value(forHTTPHeaderField: "X-CashRunway-Client") == "ios")
        #expect(request.value(forHTTPHeaderField: "X-CashRunway-Secret") == "secret")
        let requestBody = try #require(request.httpBody)
        let json = String(data: requestBody, encoding: .utf8) ?? ""
        #expect(json.contains(#""idempotencyKey":"attempt-1""#))
        let response = HTTPURLResponse(
            url: request.url!,
            statusCode: statusCode,
            httpVersion: nil,
            headerFields: nil
        )!
        return (Data(body.utf8), response)
    }
}

private extension ReportIssueService {
    static func test(statusCode: Int, body: String) -> ReportIssueService {
        ReportIssueService(
            endpointURL: URL(string: "https://reports.example.test/api/reports")!,
            clientSecret: "secret",
            transport: MockReportIssueTransport(statusCode: statusCode, body: body)
        )
    }
}
