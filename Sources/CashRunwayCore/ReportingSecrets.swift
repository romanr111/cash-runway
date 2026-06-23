import Foundation

public struct ReportingKeychainSecretProvider: Sendable {
    public static let keychainService = "cash-runway-reporting"
    public static let keychainAccount = "report-client-secret"
    public static let environmentSecretKey = "CASH_RUNWAY_REPORT_CLIENT_SECRET"

    private let keychain: any KeychainStoring
    private let environment: @Sendable () -> [String: String]
    private let bundledSecret: @Sendable () -> String?

    public init(
        keychain: any KeychainStoring = KeychainStore(service: keychainService),
        environment: @escaping @Sendable () -> [String: String] = {
            ProcessInfo.processInfo.environment
        },
        bundledSecret: @escaping @Sendable () -> String? = { nil }
    ) {
        self.keychain = keychain
        self.environment = environment
        self.bundledSecret = bundledSecret
    }

    public func clientSecret() -> String? {
        #if DEBUG
        if let secret = debugEnvironmentSecret() {
            try? keychain.write(Data(secret.utf8), account: Self.keychainAccount)
            return secret
        }
        #endif

        guard let secret = bundledSecretValue() else {
            clearSecret()
            return nil
        }

        if let existingData = try? keychain.read(account: Self.keychainAccount),
           let existing = String(data: existingData, encoding: .utf8),
           !existing.isEmpty,
           existing == secret {
            return existing
        }

        try? keychain.write(Data(secret.utf8), account: Self.keychainAccount)
        return secret
    }

    public func clearSecret() {
        keychain.delete(account: Self.keychainAccount)
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

    private func bundledSecretValue() -> String? {
        guard let secret = bundledSecret()?.trimmingCharacters(in: .whitespacesAndNewlines),
              !secret.isEmpty else {
            return nil
        }
        return secret
    }
}
