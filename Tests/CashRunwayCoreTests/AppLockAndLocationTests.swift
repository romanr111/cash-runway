import Foundation
import Testing
@testable import CashRunwayCore

@Suite(.serialized)
struct AppLockAndLocationTests {
    @Test(.disabled("App Lock is deprecated. Re-enable when work resumes."))
    func appLockSaveAndValidate() throws {
        let keychain = TestKeychainStore()
        let store = AppLockStore(keychain: keychain)
        try store.save(pin: "1234", biometrics: false, backgroundLockSeconds: 15)
        #expect(store.validate(pin: "1234") == true)
        #expect(store.validate(pin: "0000") == false)
    }

    @Test(.disabled("App Lock is deprecated. Re-enable when work resumes."))
    func appLockRejectsShortPin() {
        let keychain = TestKeychainStore()
        let store = AppLockStore(keychain: keychain)
        #expect(throws: CashRunwayError.validation("PIN must be at least 4 digits.")) {
            try store.save(pin: "123", biometrics: false, backgroundLockSeconds: 15)
        }
    }

    @Test(.disabled("App Lock is deprecated. Re-enable when work resumes."))
    func appLockConfigurationWithCorruptData() {
        let keychain = TestKeychainStore(items: ["app-lock-config": Data("not json".utf8)])
        let store = AppLockStore(keychain: keychain)
        #expect(store.configuration() == nil)
    }

    @Test(.disabled("App Lock is deprecated. Re-enable when work resumes."))
    func appLockConfigurationWhenMissing() {
        let keychain = TestKeychainStore()
        let store = AppLockStore(keychain: keychain)
        #expect(store.configuration() == nil)
        #expect(store.validate(pin: "1234") == false)
    }

    @Test(.disabled("App Lock is deprecated. Re-enable when work resumes."))
    func appLockCanUseBiometricsWhenDisabled() {
        let keychain = TestKeychainStore()
        let store = AppLockStore(keychain: keychain)
        #expect(store.canUseBiometrics() == false)
    }

    @Test func databaseLocationOverrideURL() throws {
        let baseURL = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let provider = DatabaseLocationProvider(
            appGroupIdentifier: nil,
            databaseURLOverride: baseURL.appendingPathComponent("test.sqlite"),
            directoryName: "Test"
        )
        let url = try provider.databaseURL()
        #expect(url.lastPathComponent == "test.sqlite")
        #expect(FileManager.default.fileExists(atPath: url.deletingLastPathComponent().path))
    }

    @Test func databaseLocationAppGroupFallback() throws {
        let provider = DatabaseLocationProvider(
            appGroupIdentifier: "nonexistent.group",
            directoryName: "Test"
        )
        let url = try provider.databaseURL()
        #expect(url.lastPathComponent == "cash-runway.sqlite")
    }
}
