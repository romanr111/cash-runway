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
            L10n.string("Bug")
        case .improvement:
            L10n.string("Improvement")
        }
    }
}

public enum ReportIssueScreenshotMimeType: String, Codable, Equatable, Sendable {
    case jpeg = "image/jpeg"
    case png = "image/png"
}

public struct ReportIssueScreenshot: Equatable, Sendable {
    public let data: Data
    public let mimeType: ReportIssueScreenshotMimeType
    public let filename: String

    public init(data: Data, mimeType: ReportIssueScreenshotMimeType, filename: String) {
        self.data = data
        self.mimeType = mimeType
        self.filename = filename
    }
}

public struct ReportIssueScreenshotPayload: Codable, Equatable, Sendable {
    public let data: String
    public let mimeType: String
    public let filename: String

    public init(data: String, mimeType: String, filename: String) {
        self.data = data
        self.mimeType = mimeType
        self.filename = filename
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
    public let screenshots: [ReportIssueScreenshotPayload]
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
        screenshots: [ReportIssueScreenshotPayload],
        diagnostics: ReportIssueDiagnostics?
    ) {
        self.category = category
        self.idempotencyKey = idempotencyKey
        self.title = title
        self.description = description
        self.screen = screen
        self.screenshots = screenshots
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
    public static let maxScreenshots = 3
    public static let maxScreenshotBytes = 1_048_576 // 1 MB decoded
    public static let maxTotalScreenshotBytes = 3 * maxScreenshotBytes // 3 MB decoded

    public var category: ReportIssueCategory
    public var title: String
    public var description: String
    public var screen: String?
    public var screenshots: [ReportIssueScreenshot]
    public var includeDiagnostics: Bool

    public init(
        category: ReportIssueCategory = .bug,
        title: String = "",
        description: String = "",
        screen: String? = nil,
        screenshots: [ReportIssueScreenshot] = [],
        includeDiagnostics: Bool = true
    ) {
        self.category = category
        self.title = title
        self.description = description
        self.screen = screen
        self.screenshots = screenshots
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
            return L10n.string("Title must be 5-120 characters.")
        }
        if !(20...4000).contains(trimmedDescription.count) {
            return L10n.string("Description must be 20-4000 characters.")
        }
        if screenshots.count > ReportIssueDraft.maxScreenshots {
            return L10n.string("You can attach up to %d screenshots.", ReportIssueDraft.maxScreenshots)
        }
        for screenshot in screenshots {
            if screenshot.data.count > ReportIssueDraft.maxScreenshotBytes {
                return L10n.string("Each screenshot must be smaller than 1 MB.")
            }
            if !screenshot.mimeType.matches(data: screenshot.data) {
                return L10n.string("Screenshots must be JPEG or PNG images.")
            }
        }
        let totalSize = screenshots.reduce(0) { $0 + $1.data.count }
        if totalSize > ReportIssueDraft.maxTotalScreenshotBytes {
            return L10n.string("Screenshots must be smaller than 3 MB in total.")
        }
        if containsForbiddenFinancialText(trimmedTitle) || containsForbiddenFinancialText(trimmedDescription) {
            return L10n.string(
                "Do not include account numbers, balances, transaction details, Monobank tokens, " +
                "CSV exports, database files, or raw logs."
            )
        }
        return nil
    }

    public var canSubmit: Bool {
        validationMessage == nil
    }

    public func validatedPayload(
        diagnostics: ReportIssueDiagnostics?,
        idempotencyKey: String
    ) throws -> ReportIssuePayload {
        if let validationMessage {
            throw ReportIssueValidationError.invalid(validationMessage)
        }
        return ReportIssuePayload(
            category: category,
            idempotencyKey: idempotencyKey,
            title: trimmedTitle,
            description: trimmedDescription,
            screen: sanitizedScreen,
            screenshots: screenshots.map {
                ReportIssueScreenshotPayload(
                    data: $0.data.base64EncodedString(),
                    mimeType: $0.mimeType.rawValue,
                    filename: sanitizedFilename($0.filename) ?? "screenshot.jpg"
                )
            },
            diagnostics: includeDiagnostics ? diagnostics : nil
        )
    }

    private var sanitizedScreen: String? {
        guard let screen else { return nil }
        let trimmed = screen.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : String(trimmed.prefix(100))
    }

    private func sanitizedFilename(_ filename: String) -> String? {
        let trimmed = filename.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : String(trimmed.prefix(100))
    }
}

private extension ReportIssueScreenshotMimeType {
    func matches(data: Data) -> Bool {
        switch self {
        case .jpeg:
            return data.starts(with: [0xFF, 0xD8, 0xFF])
        case .png:
            return data.starts(with: [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A])
        }
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
    private static let keychainService = "cash-runway-feedback"
    private let loadID: @Sendable () -> String?
    private let saveID: @Sendable (String) -> Void

    public init(
        loadID: @escaping @Sendable () -> String? = Self.loadFromKeychain,
        saveID: @escaping @Sendable (String) -> Void = Self.saveToKeychain
    ) {
        self.loadID = loadID
        self.saveID = saveID
    }

    public static func loadFromKeychain() -> String? {
        let keychain = KeychainStore(service: keychainService)
        if let data = try? keychain.read(account: storageKey),
           let id = String(data: data, encoding: .utf8) {
            return id
        }
        if let legacy = UserDefaults.standard.string(forKey: storageKey) {
            try? keychain.write(Data(legacy.utf8), account: storageKey)
            return legacy
        }
        return nil
    }

    public static func saveToKeychain(_ id: String) {
        try? KeychainStore(service: keychainService).write(Data(id.utf8), account: storageKey)
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
            throw ReportIssueServiceError.rateLimited(limit: rateLimitLimit(from: data, fallback: 5), remaining: rateLimitRemaining(from: data, fallback: 0), windowSeconds: 3600)
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

    private func rateLimitLimit(from data: Data, fallback: Int) -> Int {
        guard let response = try? JSONDecoder().decode(RateLimitErrorResponse.self, from: data) else {
            return fallback
        }
        return response.limit ?? fallback
    }

    private func rateLimitRemaining(from data: Data, fallback: Int) -> Int {
        guard let response = try? JSONDecoder().decode(RateLimitErrorResponse.self, from: data) else {
            return fallback
        }
        return response.remaining ?? fallback
    }
}

public enum ReportIssueServiceError: LocalizedError, Equatable, Sendable {
    case invalidResponse
    case validation(String)
    case rateLimited(limit: Int, remaining: Int, windowSeconds: Int)
    case server(Int)
    case notConfigured

    public var errorDescription: String? {
        switch self {
        case .invalidResponse:
            return L10n.string("The reporting service returned an invalid response.")
        case let .validation(message):
            return message
        case let .rateLimited(limit, remaining, _):
            let used = limit - remaining
            if used >= limit {
                return L10n.string(
                    "You've reached the limit of %lld reports this hour. Try again later.",
                    limit
                )
            } else {
                return L10n.string(
                    "You've sent %lld of %lld reports this hour. Try again later.",
                    used, limit
                )
            }
        case let .server(statusCode):
            return L10n.string("Could not create the report. Server status: %d.", statusCode)
        case .notConfigured:
            return L10n.string("Reporting is not configured yet.")
        }
    }
}

private struct ReportIssueErrorResponse: Codable {
    let error: String
}

private struct RateLimitErrorResponse: Codable {
    let limit: Int?
    let remaining: Int?
    let error: String?
}

private func containsForbiddenFinancialText(_ value: String) -> Bool {
    let lowered = value.lowercased()
    guard lowered.count <= 5000 else { return false }

    let amountPattern = #"[-+]?\d[\d\s.,]{2,}\s*(uah|usd|eur|₴|\$|€)?"#
    let secretPattern = #"[a-z0-9_\-]{16,}"#
    let patterns = [
        #"account\s+(balance|number)\s*(is|:)?\s*\#(amountPattern)"#,
        #"balance\s*(is|:)\s*\#(amountPattern)"#,
        #"monobank\s+token\s*(is|:)\s*\#(secretPattern)"#,
        #"transaction\s+(data|details)\s*(is|:)"#,
        #"database\s+file\s*(is|:)"#,
        #"raw\s+logs?\s*(are|is|:)"#
    ]
    return patterns.contains { lowered.range(of: $0, options: .regularExpression) != nil }
}

private func currentDeviceModel() -> String {
    #if canImport(Darwin)
    var systemInfo = utsname()
    uname(&systemInfo)
    let machine = withUnsafeBytes(of: &systemInfo.machine) { rawBuffer -> String in
        let bytes = Array(rawBuffer.prefix { $0 != 0 })
        return String(bytes: bytes, encoding: .utf8) ?? ""
    }
    return machine.isEmpty ? "unknown" : machine
    #else
    return "unknown"
    #endif
}
