import Foundation

public struct ReportingKeychainSecretProvider: Sendable {
    public static let keychainService = "cash-runway-reporting"
    public static let keychainAccount = "report-client-secret"

    private let keychain: any KeychainStoring

    public init(keychain: any KeychainStoring = KeychainStore(service: keychainService)) {
        self.keychain = keychain
    }

    public func clientSecret() -> String? {
        if let existing = try? keychain.read(account: Self.keychainAccount),
           let secret = String(data: existing, encoding: .utf8),
           !secret.isEmpty {
            return secret
        }
        guard !ReportingSecrets.isPlaceholder else { return nil }
        let secret = ReportingSecrets.clientSecret()
        guard !secret.isEmpty else { return nil }
        try? keychain.write(Data(secret.utf8), account: Self.keychainAccount)
        return secret
    }

    public func clearSecret() {
        keychain.delete(account: Self.keychainAccount)
    }
}
