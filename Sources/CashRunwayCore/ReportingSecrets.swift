import Foundation

public struct ReportingKeychainSecretProvider: Sendable {
    public static let keychainService = "cash-runway-reporting"
    public static let keychainAccount = "report-client-secret"
    public static let environmentSecretKey = "CASH_RUNWAY_REPORT_CLIENT_SECRET"

    private let keychain: any KeychainStoring
    private let environment: @Sendable () -> [String: String]
    private let isPlaceholder: Bool

    public init(
        keychain: any KeychainStoring = KeychainStore(service: keychainService),
        environment: @escaping @Sendable () -> [String: String] = { ProcessInfo.processInfo.environment },
        isPlaceholder: Bool
    ) {
        self.keychain = keychain
        self.environment = environment
        self.isPlaceholder = isPlaceholder
    }

    public init(
        keychain: any KeychainStoring = KeychainStore(service: keychainService),
        environment: @escaping @Sendable () -> [String: String] = { ProcessInfo.processInfo.environment }
    ) {
        self.isPlaceholder = ReportingSecrets.isPlaceholder
        self.keychain = keychain
        self.environment = environment
    }

    public func clientSecret() -> String? {
        #if DEBUG
        if let secret = debugEnvironmentSecret() {
            try? keychain.write(Data(secret.utf8), account: Self.keychainAccount)
            return secret
        }
        #endif

        if isPlaceholder {
            clearSecret()
            return nil
        }

        let generatedSecret = ReportingSecrets.clientSecret()
        guard !generatedSecret.isEmpty else {
            return nil
        }

        if let existing = try? keychain.read(account: Self.keychainAccount),
           let secret = String(data: existing, encoding: .utf8),
           !secret.isEmpty,
           secret == generatedSecret {
            return secret
        }

        try? keychain.write(Data(generatedSecret.utf8), account: Self.keychainAccount)
        return generatedSecret
    }

    #if DEBUG
    private func debugEnvironmentSecret() -> String? {
        guard let secret = environment()[Self.environmentSecretKey]?.trimmingCharacters(in: .whitespacesAndNewlines),
              !secret.isEmpty else {
            return nil
        }
        return secret
    }
    #endif

    public func clearSecret() {
        keychain.delete(account: Self.keychainAccount)
    }
}
