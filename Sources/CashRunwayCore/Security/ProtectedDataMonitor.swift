import Foundation
import OSLog

#if canImport(UIKit)
import UIKit
#endif

/// Tracks whether the device’s protected data is currently available.
///
/// When `NSFileProtectionComplete` is active, files are inaccessible while the
/// device is locked. Background work that touches the database must check this
/// state and defer safely rather than fail or fall back to a weaker class.
public final class ProtectedDataMonitor: @unchecked Sendable {
    private static let logger = Logger(subsystem: "dev.roman.cashrunway", category: "protected-data")

    /// Shared monitor. Tests should prefer injecting a custom `ProtectedDataMonitoring`
    /// instance rather than mutating this singleton.
    public static let shared = ProtectedDataMonitor()

    private var overrideState: ProtectedDataState?

    public init() {}

    /// For testing only. `nil` means read the real UIKit state.
    public func setOverride(_ state: ProtectedDataState?) {
        overrideState = state
    }

    public var state: ProtectedDataState {
        if let overrideState { return overrideState }
        return Self.systemState()
    }

    public var isAvailable: Bool {
        switch state {
        case .available:
            return true
        case .unavailable:
            return false
        }
    }

    private static func systemState() -> ProtectedDataState {
        #if canImport(UIKit)
        if Thread.isMainThread {
            return UIApplication.shared.isProtectedDataAvailable
                ? .available
                : .unavailable(reason: "UIApplication.shared.isProtectedDataAvailable is false")
        }
        // UIApplication state must be read on the main actor.
        let available = DispatchQueue.main.sync {
            UIApplication.shared.isProtectedDataAvailable
        }
        return available ? .available : .unavailable(reason: "UIApplication.shared.isProtectedDataAvailable is false")
        #else
        // SwiftPM tests run without UIKit; treat protected data as available so
        // database work is not silently skipped. On iOS, the real UIKit state is used.
        return .available
        #endif
    }

    /// Logs a privacy-safe debug message and returns `true` if the caller should skip work.
    @discardableResult
    public static func skipIfUnavailable(_ monitor: ProtectedDataMonitoring? = nil, work: StaticString) -> Bool {
        let target = monitor ?? shared
        guard !target.isAvailable else { return false }
        logger.debug("Skipping \(work, privacy: .public): protected data unavailable.")
        return true
    }
}

public enum ProtectedDataState: Equatable, Sendable {
    case available
    case unavailable(reason: String)
}

public protocol ProtectedDataMonitoring: Sendable {
    var isAvailable: Bool { get }
}

extension ProtectedDataMonitor: ProtectedDataMonitoring {}
