import Foundation
import OSLog

/// Applies `NSFileProtectionComplete` to files that may contain Cash Runway data.
///
/// The entitlement `com.apple.developer.default-data-protection` declares the
/// default protection class, but files should still be tagged explicitly so the
/// attribute is correct even when created outside the app container or by tools
/// that do not inherit the entitlement default (e.g., during recovery or backup).
public struct FileProtectionService: Sendable {
    private static let logger = Logger(subsystem: "dev.roman.cashrunway", category: "file-protection")

    public init() {}

    /// Apply `NSFileProtectionComplete` to a single file.
    ///
    /// Missing files are ignored so callers can protect paths before they exist.
    public func protect(_ url: URL) {
        let path = url.path
        guard FileManager.default.fileExists(atPath: path) else {
            Self.logger.debug("Skipping protection for missing file: \(path, privacy: .private)")
            return
        }
        do {
            try FileManager.default.setAttributes(
                [.protectionKey: FileProtectionType.complete],
                ofItemAtPath: path
            )
            Self.logger.debug("Applied complete protection: \(path, privacy: .private)")
        } catch {
            Self.logger.error("Failed to apply complete protection to \(path, privacy: .private): \(error.localizedDescription, privacy: .public)")
        }
    }

    /// Apply `NSFileProtectionComplete` to the SQLite database and its WAL/SHM siblings.
    public func protectSQLiteTrio(at databaseURL: URL) {
        let basePath = databaseURL.path
        protect(databaseURL)
        protect(URL(fileURLWithPath: basePath + "-wal"))
        protect(URL(fileURLWithPath: basePath + "-shm"))
    }
}
