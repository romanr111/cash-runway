import Foundation

public struct ReportingKeychainSecretProvider: Sendable {
    public static let keychainService = "cash-runway-reporting"
    public static let keychainAccount = "report-client-secret"
    public static let environmentSecretKey = "CASH_RUNWAY_REPORT_CLIENT_SECRET"

    private let keychain: any KeychainStoring
    private let environment: @Sendable () -> [String: String]

    public init(
        keychain: any KeychainStoring = KeychainStore(service: keychainService),
        environment: @escaping @Sendable () -> [String: String] = { ProcessInfo.processInfo.environment }
    ) {
        self.keychain = keychain
        self.environment = environment
    }

    public func clientSecret() -> String? {
        if let existing = try? keychain.read(account: Self.keychainAccount),
           let secret = String(data: existing, encoding: .utf8),
           !secret.isEmpty {
            return secret
        }

        #if DEBUG
        if let secret = environment()[Self.environmentSecretKey]?.trimmingCharacters(in: .whitespacesAndNewlines),
           !secret.isEmpty {
            try? keychain.write(Data(secret.utf8), account: Self.keychainAccount)
            return secret
        }
        #endif

        guard !ReportingSecrets.isPlaceholder else {
            return nil
        }

        let secret = ReportingSecrets.clientSecret()
        guard !secret.isEmpty else {
            return nil
        }
        try? keychain.write(Data(secret.utf8), account: Self.keychainAccount)
        return secret
    }

    public func clearSecret() {
        keychain.delete(account: Self.keychainAccount)
    }
}
