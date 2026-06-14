import CryptoKit
import Foundation

@MainActor
protocol FeedbackReportSubmitting: Sendable {
    var unavailableMessage: String? { get }
    func submit(_ draft: ReportIssueDraft, idempotencyKey: String) async throws -> ReportIssueResponse
}

struct ConfiguredFeedbackReportService: FeedbackReportSubmitting {
    let unavailableMessage: String?
    private let reportService: ReportIssueService?
    private let diagnosticsProvider: SafeDiagnosticsProvider

    init(
        config: ReportingConfig = .bundleDefault,
        secretProvider: ReportingKeychainSecretProvider = ReportingKeychainSecretProvider(
            environment: {
                var env = ProcessInfo.processInfo.environment
                if env[ReportingKeychainSecretProvider.environmentSecretKey] == nil,
                   let plist = Bundle.main.object(forInfoDictionaryKey: "CashRunwayReportClientSecret") as? String,
                   !plist.isEmpty, plist != "replace-with-your-report-secret" {
                    env[ReportingKeychainSecretProvider.environmentSecretKey] = plist
                }
                return env
            }
        ),
        diagnosticsProvider: SafeDiagnosticsProvider = SafeDiagnosticsProvider()
    ) {
        let configMessage = config.unavailableMessage
        if configMessage == nil,
           let endpointURL = config.endpointURL,
           let clientSecret = secretProvider.clientSecret() {
            reportService = ReportIssueService(endpointURL: endpointURL, clientSecret: clientSecret)
            unavailableMessage = nil
        } else {
            reportService = nil
            unavailableMessage = configMessage ?? L10n.string("Reporting is not configured yet.")
        }
        self.diagnosticsProvider = diagnosticsProvider
    }

    func submit(_ draft: ReportIssueDraft, idempotencyKey: String) async throws -> ReportIssueResponse {
        guard let reportService else {
            throw ReportIssueServiceError.notConfigured
        }
        let payload = try draft.validatedPayload(
            diagnostics: diagnosticsProvider.diagnostics(),
            idempotencyKey: idempotencyKey
        )
        return try await reportService.submit(payload)
    }
}

struct MockFeedbackReportService: FeedbackReportSubmitting {
    var unavailableMessage: String?
    var response = ReportIssueResponse(status: "created", issueNumber: 123)
    var error: Error?

    func submit(_ draft: ReportIssueDraft, idempotencyKey: String) async throws -> ReportIssueResponse {
        _ = try draft.validatedPayload(diagnostics: nil, idempotencyKey: idempotencyKey)
        if let error {
            throw error
        }
        return response
    }
}

@MainActor
final class ReportIssueViewModel: ObservableObject {
    @Published var draft = ReportIssueDraft()
    @Published private(set) var submitState: ReportIssueSubmitState = .idle

    private let service: any FeedbackReportSubmitting
    private var activeAttemptKey: String?
    private var activeAttemptFingerprint: String?

    init(service: any FeedbackReportSubmitting) {
        self.service = service
    }

    var isSubmitting: Bool {
        if case .submitting = submitState {
            return true
        }
        return false
    }

    var isLocked: Bool {
        isSubmitting || submitState.isSuccess
    }

    var canSubmit: Bool {
        service.unavailableMessage == nil && draft.canSubmit && !isSubmitting && !submitState.isSuccess
    }

    var unavailableMessage: String? {
        service.unavailableMessage
    }

    func submit() {
        guard canSubmit else { return }
        let idempotencyKey = idempotencyKeyForCurrentDraft()
        Task {
            do {
                submitState = .submitting
                let response = try await service.submit(draft, idempotencyKey: idempotencyKey)
                submitState = .success(response.issueNumber)
            } catch {
                submitState = .failure(error.localizedDescription)
            }
        }
    }

    private func idempotencyKeyForCurrentDraft() -> String {
        let fingerprint = [
            draft.category.rawValue,
            draft.trimmedTitle,
            draft.trimmedDescription,
            draft.screen ?? "",
            String(draft.includeDiagnostics),
            screenshotFingerprint()
        ].joined(separator: "\n")
        if activeAttemptFingerprint != fingerprint {
            activeAttemptFingerprint = fingerprint
            activeAttemptKey = UUID().uuidString
        }
        if let activeAttemptKey {
            return activeAttemptKey
        }
        let created = UUID().uuidString
        activeAttemptKey = created
        return created
    }

    private func screenshotFingerprint() -> String {
        draft.screenshots.map { screenshotDataHash($0.data) }.joined(separator: ",")
    }

    private func screenshotDataHash(_ data: Data) -> String {
        SHA256.hash(data: data).compactMap { String(format: "%02x", $0) }.joined()
    }
}

enum ReportIssueSubmitState: Equatable {
    case idle
    case submitting
    case success(Int)
    case failure(String)

    var isSuccess: Bool {
        if case .success = self {
            return true
        }
        return false
    }
}

enum ReportingEnvironment: String, Equatable, Sendable {
    case debug
    case staging
    case production
}

struct ReportingConfig: Equatable, Sendable {
    let endpointURL: URL?
    let isReportingEnabled: Bool
    let environment: ReportingEnvironment

    var unavailableMessage: String? {
        guard isReportingEnabled else {
            return L10n.string("Reporting is currently disabled.")
        }
        guard let endpointURL, !endpointURL.isPlaceholderReportingURL else {
            return L10n.string("Reporting is not configured yet.")
        }
        return nil
    }

    static var bundleDefault: ReportingConfig {
        ReportingConfig(bundle: .main)
    }

    init(
        endpointURL: URL?,
        isReportingEnabled: Bool,
        environment: ReportingEnvironment
    ) {
        self.endpointURL = endpointURL
        self.isReportingEnabled = isReportingEnabled
        self.environment = environment
    }

    init(bundle: Bundle) {
        endpointURL = bundle.reportIssueEndpointURL
        isReportingEnabled = bundle.reportIssueEnabled
        environment = bundle.reportIssueEnvironment
    }
}

private extension URL {
    var isPlaceholderReportingURL: Bool {
        absoluteString.contains("replace-with") || host == "reports.example.test"
    }
}

private extension Bundle {
    var reportIssueEndpointURL: URL? {
        guard let value = object(forInfoDictionaryKey: "CashRunwayReportEndpointURL") as? String else {
            return nil
        }
        return URL(string: value)
    }

    var reportIssueEnabled: Bool {
        guard let value = object(forInfoDictionaryKey: "CashRunwayReportingEnabled") else {
            return true
        }
        if let bool = value as? Bool {
            return bool
        }
        if let string = value as? String {
            return !["false", "0", "no"].contains(string.lowercased())
        }
        return false
    }

    var reportIssueEnvironment: ReportingEnvironment {
        if let value = object(forInfoDictionaryKey: "CashRunwayReportEnvironment") as? String,
           let environment = ReportingEnvironment(rawValue: value.lowercased()) {
            return environment
        }
        #if DEBUG
        return .debug
        #else
        return .production
        #endif
    }
}
