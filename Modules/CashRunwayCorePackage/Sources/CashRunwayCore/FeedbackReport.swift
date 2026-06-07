import CryptoKit
import Foundation

#if canImport(Darwin)
import Darwin
#endif

public enum ReportIssueCategory: String, CaseIterable, Identifiable, Codable, Sendable {
    case bug
    case improvement

    public var id: String { rawValue }

    public var displayTitle: String {
        switch self {
        case .bug:
            "Bug"
        case .improvement:
            "Improvement"
        }
    }
}

public struct ReportIssueDiagnostics: Codable, Equatable, Sendable {
    public let appVersion: String
    public let buildNumber: String
    public let iosVersion: String
    public let deviceModel: String
    public let locale: String
    public let timezone: String
    public let installHash: String

    public init(
        appVersion: String,
        buildNumber: String,
        iosVersion: String,
        deviceModel: String,
        locale: String,
        timezone: String,
        installHash: String
    ) {
        self.appVersion = appVersion
        self.buildNumber = buildNumber
        self.iosVersion = iosVersion
        self.deviceModel = deviceModel
        self.locale = locale
        self.timezone = timezone
        self.installHash = installHash
    }
}

public struct ReportIssuePayload: Codable, Equatable, Sendable {
    public let category: ReportIssueCategory
    public let idempotencyKey: String
    public let title: String
    public let description: String
    public let screen: String?
    public let appVersion: String?
    public let buildNumber: String?
    public let iosVersion: String?
    public let deviceModel: String?
    public let locale: String?
    public let timezone: String?
    public let installHash: String?

    public init(
        category: ReportIssueCategory,
        idempotencyKey: String,
        title: String,
        description: String,
        screen: String?,
        diagnostics: ReportIssueDiagnostics?
    ) {
        self.category = category
        self.idempotencyKey = idempotencyKey
        self.title = title
        self.description = description
        self.screen = screen
        appVersion = diagnostics?.appVersion
        buildNumber = diagnostics?.buildNumber
        iosVersion = diagnostics?.iosVersion
        deviceModel = diagnostics?.deviceModel
        locale = diagnostics?.locale
        timezone = diagnostics?.timezone
        installHash = diagnostics?.installHash
    }
}

public struct ReportIssueDraft: Equatable, Sendable {
    public var category: ReportIssueCategory
    public var title: String
    public var description: String
    public var screen: String?
    public var includeDiagnostics: Bool

    public init(
        category: ReportIssueCategory = .bug,
        title: String = "",
        description: String = "",
        screen: String? = nil,
        includeDiagnostics: Bool = true
    ) {
        self.category = category
        self.title = title
        self.description = description
        self.screen = screen
        self.includeDiagnostics = includeDiagnostics
    }

    public var trimmedTitle: String {
        title.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    public var trimmedDescription: String {
        description.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    public var validationMessage: String? {
        if !(5...120).contains(trimmedTitle.count) {
            return "Title must be 5-120 characters."
        }
        if !(20...4000).contains(trimmedDescription.count) {
            return "Description must be 20-4000 characters."
        }
        if containsForbiddenFinancialText(trimmedTitle) || containsForbiddenFinancialText(trimmedDescription) {
            return "Do not include account numbers, balances, transaction details, Monobank tokens, CSV exports, database files, screenshots, or logs."
        }
        return nil
    }

    public var canSubmit: Bool {
        validationMessage == nil
    }

    public func validatedPayload(diagnostics: ReportIssueDiagnostics?, idempotencyKey: String) throws -> ReportIssuePayload {
        if let validationMessage {
            throw ReportIssueValidationError.invalid(validationMessage)
        }
        return ReportIssuePayload(
            category: category,
            idempotencyKey: idempotencyKey,
            title: trimmedTitle,
            description: trimmedDescription,
            screen: sanitizedScreen,
            diagnostics: includeDiagnostics ? diagnostics : nil
        )
    }

    private var sanitizedScreen: String? {
        guard let screen else { return nil }
        let trimmed = screen.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : String(trimmed.prefix(100))
    }
}

public enum ReportIssueValidationError: LocalizedError, Equatable, Sendable {
    case invalid(String)

    public var errorDescription: String? {
        switch self {
        case let .invalid(message):
            message
        }
    }
}

public struct AnonymousInstallIDProvider: Sendable {
    public static let storageKey = "cashRunway.anonymousInstallID"
    private let loadID: @Sendable () -> String?
    private let saveID: @Sendable (String) -> Void

    public init(
        loadID: @escaping @Sendable () -> String? = {
            UserDefaults.standard.string(forKey: AnonymousInstallIDProvider.storageKey)
        },
        saveID: @escaping @Sendable (String) -> Void = {
            UserDefaults.standard.set($0, forKey: AnonymousInstallIDProvider.storageKey)
        }
    ) {
        self.loadID = loadID
        self.saveID = saveID
    }

    public func installHash() -> String {
        let id: String
        if let existing = loadID() {
            id = existing
        } else {
            let created = UUID().uuidString
            saveID(created)
            id = created
        }
        let digest = SHA256.hash(data: Data(id.utf8))
        return "sha256:" + digest.map { String(format: "%02x", $0) }.joined()
    }
}

public struct SafeDiagnosticsProvider: Sendable {
    private let installIDProvider: AnonymousInstallIDProvider
    private let bundle: Bundle
    private let processInfo: ProcessInfo

    public init(
        installIDProvider: AnonymousInstallIDProvider = AnonymousInstallIDProvider(),
        bundle: Bundle = .main,
        processInfo: ProcessInfo = .processInfo
    ) {
        self.installIDProvider = installIDProvider
        self.bundle = bundle
        self.processInfo = processInfo
    }

    public func diagnostics() -> ReportIssueDiagnostics {
        ReportIssueDiagnostics(
            appVersion: bundle.infoDictionary?["CFBundleShortVersionString"] as? String ?? "unknown",
            buildNumber: bundle.infoDictionary?["CFBundleVersion"] as? String ?? "unknown",
            iosVersion: processInfo.operatingSystemVersionString,
            deviceModel: currentDeviceModel(),
            locale: Locale.current.identifier,
            timezone: TimeZone.current.identifier,
            installHash: installIDProvider.installHash()
        )
    }
}

public struct ReportIssueResponse: Codable, Equatable, Sendable {
    public let status: String
    public let issueNumber: Int
}

public protocol ReportIssueTransport: Sendable {
    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse)
}

public struct URLSessionReportIssueTransport: ReportIssueTransport {
    public init() {}

    public func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw ReportIssueServiceError.invalidResponse
        }
        return (data, httpResponse)
    }
}

public struct ReportIssueService: Sendable {
    public let endpointURL: URL
    public let clientSecret: String
    private let transport: any ReportIssueTransport

    public init(
        endpointURL: URL,
        clientSecret: String,
        transport: any ReportIssueTransport = URLSessionReportIssueTransport()
    ) {
        self.endpointURL = endpointURL
        self.clientSecret = clientSecret
        self.transport = transport
    }

    public func submit(_ payload: ReportIssuePayload) async throws -> ReportIssueResponse {
        var request = URLRequest(url: endpointURL)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("ios", forHTTPHeaderField: "X-CashRunway-Client")
        request.setValue(clientSecret, forHTTPHeaderField: "X-CashRunway-Secret")
        request.httpBody = try JSONEncoder().encode(payload)

        let (data, response) = try await transport.send(request)
        switch response.statusCode {
        case 200...299:
            return try JSONDecoder().decode(ReportIssueResponse.self, from: data)
        case 400:
            throw ReportIssueServiceError.validation(errorMessage(from: data) ?? "Invalid report.")
        case 429:
            throw ReportIssueServiceError.rateLimited
        default:
            throw ReportIssueServiceError.server(response.statusCode)
        }
    }

    private func errorMessage(from data: Data) -> String? {
        guard let errorResponse = try? JSONDecoder().decode(ReportIssueErrorResponse.self, from: data) else {
            return nil
        }
        return errorResponse.error
    }
}

public enum ReportIssueServiceError: LocalizedError, Equatable, Sendable {
    case invalidResponse
    case validation(String)
    case rateLimited
    case server(Int)
    case notConfigured

    public var errorDescription: String? {
        switch self {
        case .invalidResponse:
            "The reporting service returned an invalid response."
        case let .validation(message):
            message
        case .rateLimited:
            "Too many reports were sent. Try again later."
        case let .server(statusCode):
            "Could not create the report. Server status: \(statusCode)."
        case .notConfigured:
            "Reporting is not configured yet."
        }
    }
}

private struct ReportIssueErrorResponse: Codable {
    let error: String
}

private func containsForbiddenFinancialText(_ value: String) -> Bool {
    let lowered = value.lowercased()
    let amountPattern = #"[-+]?\d[\d\s.,]{2,}\s*(uah|usd|eur|₴|\$|€)?"#
    let secretPattern = #"[a-z0-9_\-]{16,}"#
    return lowered.range(of: #"account\s+(balance|number)\s*(is|:)?\s*\#(amountPattern)"#, options: .regularExpression) != nil
        || lowered.range(of: #"balance\s*(is|:)\s*\#(amountPattern)"#, options: .regularExpression) != nil
        || lowered.range(of: #"monobank\s+token\s*(is|:)\s*\#(secretPattern)"#, options: .regularExpression) != nil
        || lowered.range(of: #"transaction\s+(data|details)\s*(is|:)"#, options: .regularExpression) != nil
        || lowered.range(of: #"database\s+file\s*(is|:)"#, options: .regularExpression) != nil
        || lowered.range(of: #"raw\s+logs?\s*(are|is|:)"#, options: .regularExpression) != nil
}

private func currentDeviceModel() -> String {
    #if canImport(Darwin)
    var systemInfo = utsname()
    uname(&systemInfo)
    let machine = withUnsafeBytes(of: &systemInfo.machine) { rawBuffer -> String in
        let bytes = rawBuffer.prefix { $0 != 0 }
        return String(decoding: bytes, as: UTF8.self)
    }
    return machine.isEmpty ? "unknown" : machine
    #else
    return "unknown"
    #endif
}
