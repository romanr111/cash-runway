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
            screenshots: [],
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
    }

    @Test func draftValidationRejectsInvalidTitle() {
        var draft = ReportIssueDraft()
        draft.title = "Bug"
        draft.description = "The app crashes after selecting a CSV file."

        #expect(throws: ReportIssueValidationError.invalid(L10n.string("Title must be 5-120 characters."))) {
            _ = try draft.validatedPayload(diagnostics: nil, idempotencyKey: "attempt-1")
        }
    }

    @Test func draftValidationRejectsInvalidDescription() {
        var draft = ReportIssueDraft()
        draft.title = "CSV import crashes"
        draft.description = "Too short"

        #expect(throws: ReportIssueValidationError.invalid(L10n.string("Description must be 20-4000 characters."))) {
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

        let expected = L10n.string("Do not include account numbers, balances, transaction details, Monobank tokens, CSV exports, database files, or raw logs.")
        #expect(throws: ReportIssueValidationError.invalid(expected)) {
            _ = try balanceDraft.validatedPayload(diagnostics: nil, idempotencyKey: "attempt-1")
        }
        #expect(throws: ReportIssueValidationError.invalid(expected)) {
            _ = try tokenDraft.validatedPayload(diagnostics: nil, idempotencyKey: "attempt-1")
        }
    }

    @Test func categoryMapsToBackendString() throws {
        #expect(ReportIssueCategory.bug.rawValue == "bug")
        #expect(ReportIssueCategory.improvement.rawValue == "improvement")
    }

    @Test func categoryDisplayTitleUsesLocalization() {
        #expect(ReportIssueCategory.bug.displayTitle == L10n.string("Bug"))
        #expect(ReportIssueCategory.improvement.displayTitle == L10n.string("Improvement"))
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

    @Test func installHashPersistsInKeychain() throws {
        let keychain = TestKeychainStore()
        let provider = AnonymousInstallIDProvider(
            loadID: {
                guard let data = try? keychain.read(account: AnonymousInstallIDProvider.storageKey) else { return nil }
                return String(data: data, encoding: .utf8)
            },
            saveID: { id in
                try? keychain.write(Data(id.utf8), account: AnonymousInstallIDProvider.storageKey)
            }
        )

        let firstHash = provider.installHash()
        let secondHash = provider.installHash()

        #expect(firstHash == secondHash)
        #expect(firstHash.hasPrefix("sha256:"))
    }

    #if DEBUG
    @Test func reportingKeychainSecretProviderStoresDebugEnvironmentSecret() throws {
        let keychain = TestKeychainStore()
        let provider = ReportingKeychainSecretProvider(
            keychain: keychain,
            environment: {
                [ReportingKeychainSecretProvider.environmentSecretKey: "debug-secret"]
            }
        )

        #expect(provider.clientSecret() == "debug-secret")
        let stored = try #require(try keychain.read(account: ReportingKeychainSecretProvider.keychainAccount))
        #expect(String(data: stored, encoding: .utf8) == "debug-secret")
    }

    @Test func reportingKeychainSecretProviderLetsDebugEnvironmentOverrideStoredSecret() throws {
        let keychain = TestKeychainStore()
        try keychain.write(Data("stale-secret".utf8), account: ReportingKeychainSecretProvider.keychainAccount)
        let provider = ReportingKeychainSecretProvider(
            keychain: keychain,
            environment: {
                [ReportingKeychainSecretProvider.environmentSecretKey: "fresh-debug-secret"]
            }
        )

        #expect(provider.clientSecret() == "fresh-debug-secret")
        let stored = try #require(try keychain.read(account: ReportingKeychainSecretProvider.keychainAccount))
        #expect(String(data: stored, encoding: .utf8) == "fresh-debug-secret")
    }
    #endif

    @Test func reportingKeychainSecretProviderStoresBundledSecret() throws {
        let keychain = TestKeychainStore()
        let provider = ReportingKeychainSecretProvider(
            keychain: keychain,
            bundledSecret: { "bundled-secret" }
        )

        #expect(provider.clientSecret() == "bundled-secret")
        let stored = try #require(try keychain.read(account: ReportingKeychainSecretProvider.keychainAccount))
        #expect(String(data: stored, encoding: .utf8) == "bundled-secret")
    }

    @Test func reportingKeychainSecretProviderReusesMatchingKeychainValue() throws {
        let keychain = TestKeychainStore()
        try keychain.write(Data("bundled-secret".utf8), account: ReportingKeychainSecretProvider.keychainAccount)

        let provider = ReportingKeychainSecretProvider(
            keychain: keychain,
            bundledSecret: { "bundled-secret" }
        )

        #expect(provider.clientSecret() == "bundled-secret")
    }

    @Test func reportingKeychainSecretProviderRotatesStaleKeychainValue() throws {
        let keychain = TestKeychainStore()
        try keychain.write(Data("stale-secret".utf8), account: ReportingKeychainSecretProvider.keychainAccount)

        let provider = ReportingKeychainSecretProvider(
            keychain: keychain,
            bundledSecret: { "fresh-secret" }
        )

        #expect(provider.clientSecret() == "fresh-secret")
        let stored = try #require(try keychain.read(account: ReportingKeychainSecretProvider.keychainAccount))
        #expect(String(data: stored, encoding: .utf8) == "fresh-secret")
    }

    @Test func reportingKeychainSecretProviderClearsStaleSecretWhenBundledIsNil() throws {
        let keychain = TestKeychainStore()
        try keychain.write(Data("stale-secret".utf8), account: ReportingKeychainSecretProvider.keychainAccount)

        let provider = ReportingKeychainSecretProvider(
            keychain: keychain,
            bundledSecret: { nil }
        )

        #expect(provider.clientSecret() == nil)
        #expect(try keychain.read(account: ReportingKeychainSecretProvider.keychainAccount) == nil)
    }

    @Test func reportingKeychainSecretProviderClearsStaleSecretWhenBundledIsEmpty() throws {
        let keychain = TestKeychainStore()
        try keychain.write(Data("stale-secret".utf8), account: ReportingKeychainSecretProvider.keychainAccount)

        let provider = ReportingKeychainSecretProvider(
            keychain: keychain,
            bundledSecret: { "" }
        )

        #expect(provider.clientSecret() == nil)
        #expect(try keychain.read(account: ReportingKeychainSecretProvider.keychainAccount) == nil)
    }

    @Test func reportingKeychainSecretProviderReturnsNilWithMissingBundledSecret() {
        let keychain = TestKeychainStore()
        let provider = ReportingKeychainSecretProvider(
            keychain: keychain,
            bundledSecret: { nil }
        )

        #expect(provider.clientSecret() == nil)
    }

    @Test func reportingKeychainSecretProviderReturnsNilWithEmptyBundledSecret() {
        let keychain = TestKeychainStore()
        let provider = ReportingKeychainSecretProvider(
            keychain: keychain,
            bundledSecret: { "" }
        )

        #expect(provider.clientSecret() == nil)
    }

    @Test func reportingKeychainSecretProviderReturnsNilWithoutSideEffectsWhenUnconfigured() {
        let keychain = TestKeychainStore()
        let provider = ReportingKeychainSecretProvider(keychain: keychain)

        #expect(provider.clientSecret() == nil)
        let data = try? keychain.read(account: ReportingKeychainSecretProvider.keychainAccount)
        #expect(data == nil)
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
        await #expect(throws: ReportIssueServiceError.rateLimited(limit: 10, remaining: 0, windowSeconds: 3600)) {
            _ = try await ReportIssueService.test(statusCode: 429, body: #"{"error":"Too many reports."}"#).submit(payload)
        }
        await #expect(throws: ReportIssueServiceError.server(502)) {
            _ = try await ReportIssueService.test(statusCode: 502, body: #"{"error":"Could not create GitHub issue."}"#).submit(payload)
        }
    }

    @Test func draftValidationAcceptsValidScreenshots() throws {
        let draft = ReportIssueDraft(
            title: "CSV import crashes",
            description: "The app crashes after selecting a CSV file.",
            screenshots: [ReportIssueScreenshot(data: jpegData(), mimeType: .jpeg, filename: "screenshot.jpg")]
        )

        let payload = try draft.validatedPayload(diagnostics: nil, idempotencyKey: "attempt-1")

        #expect(payload.screenshots.count == 1)
        #expect(payload.screenshots[0].mimeType == "image/jpeg")
        #expect(!payload.screenshots[0].data.isEmpty)
    }

    @Test func draftValidationRejectsTooManyScreenshots() {
        let draft = ReportIssueDraft(
            title: "CSV import crashes",
            description: "The app crashes after selecting a CSV file.",
            screenshots: Array(repeating: ReportIssueScreenshot(data: jpegData(), mimeType: .jpeg, filename: "s.jpg"), count: 4)
        )

        #expect(throws: ReportIssueValidationError.invalid(L10n.string("You can attach up to %d screenshots.", ReportIssueDraft.maxScreenshots))) {
            _ = try draft.validatedPayload(diagnostics: nil, idempotencyKey: "attempt-1")
        }
    }

    @Test func draftValidationRejectsOversizedScreenshot() {
        let oversized = Data(repeating: 0xFF, count: 1_048_577)
        let draft = ReportIssueDraft(
            title: "CSV import crashes",
            description: "The app crashes after selecting a CSV file.",
            screenshots: [ReportIssueScreenshot(data: oversized, mimeType: .jpeg, filename: "big.jpg")]
        )

        #expect(throws: ReportIssueValidationError.invalid(L10n.string("Each screenshot must be smaller than 1 MB."))) {
            _ = try draft.validatedPayload(diagnostics: nil, idempotencyKey: "attempt-1")
        }
    }

    @Test func draftValidationRejectsInvalidImageFormat() {
        let draft = ReportIssueDraft(
            title: "CSV import crashes",
            description: "The app crashes after selecting a CSV file.",
            screenshots: [ReportIssueScreenshot(data: Data("not an image".utf8), mimeType: .jpeg, filename: "fake.jpg")]
        )

        #expect(throws: ReportIssueValidationError.invalid(L10n.string("Screenshots must be JPEG or PNG images."))) {
            _ = try draft.validatedPayload(diagnostics: nil, idempotencyKey: "attempt-1")
        }
    }

    private func validPayload(idempotencyKey: String = "attempt-1") -> ReportIssuePayload {
        ReportIssuePayload(
            category: .bug,
            idempotencyKey: idempotencyKey,
            title: "CSV import crashes",
            description: "The app crashes after selecting a CSV file.",
            screen: "CSVImportView",
            screenshots: [],
            diagnostics: nil
        )
    }

    private func jpegData() -> Data {
        Data([0xFF, 0xD8, 0xFF, 0xE0, 0x00, 0x10, 0x4A, 0x46, 0x49, 0x46])
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
