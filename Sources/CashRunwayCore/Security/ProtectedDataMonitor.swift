import Foundation
import OSLog
import os

#if canImport(UIKit)
import UIKit
#endif

/// Tracks whether the device’s protected data is currently available.
///
/// When `NSFileProtectionComplete` is active, files are inaccessible while the
/// device is locked. Background work that touches the database must check this
/// state and defer safely rather than fail or fall back to a weaker class.
public final class ProtectedDataMonitor: @unchecked Sendable {
    // @unchecked Sendable is justified: the only mutable state (overrideState,
    // cachedSystemAvailable) is protected by OSAllocatedUnfairLock. The observers
    // array holds immutable NSObjectProtocol tokens assigned once in init and read
    // only in deinit; it is never accessed concurrently. NSObjectProtocol is not
    // Sendable, which prevents deriving Sendable automatically.
    private static let logger = Logger(subsystem: "dev.roman.cashrunway", category: "protected-data")

    /// Shared monitor. Tests should prefer injecting a custom `ProtectedDataMonitoring`
    /// instance rather than mutating this singleton.
    public static let shared = ProtectedDataMonitor()

    private let overrideState = OSAllocatedUnfairLock<ProtectedDataState?>(initialState: nil)

    private var observers: [NSObjectProtocol] = []

    #if canImport(UIKit)
    /// Last cached value of `UIApplication.shared.isProtectedDataAvailable`, updated
    /// by `protectedDataDidBecomeAvailable`/`protectedDataWillBecomeUnavailable`
    /// observers. `nil` means "unknown" — the monitor has not yet observed a
    /// notification. Reads off the main thread consult this cache instead of hopping
    /// to the main queue (which would risk deadlock under Swift Concurrency's
    /// cooperative threading).
    private let cachedSystemAvailable = OSAllocatedUnfairLock<Bool?>(initialState: nil)
    #endif

    public init() {
        #if canImport(UIKit)
        // UIKit posts both notifications on the main thread, so the observer
        // callbacks run on main and may safely write cachedSystemAvailable.
        let center = NotificationCenter.default
        let didBecomeAvailable = center.addObserver(
            forName: UIApplication.protectedDataDidBecomeAvailableNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.cacheSystemAvailability()
        }
        let willBecomeUnavailable = center.addObserver(
            forName: UIApplication.protectedDataWillBecomeUnavailableNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.cacheSystemAvailability()
        }
        observers = [didBecomeAvailable, willBecomeUnavailable]
        // Seed the cache opportunistically if init happens on the main thread.
        if Thread.isMainThread { cacheSystemAvailability() }
        #endif
    }

    deinit {
        #if canImport(UIKit)
        for observer in observers { NotificationCenter.default.removeObserver(observer) }
        #endif
    }

    #if canImport(UIKit)
    private func cacheSystemAvailability() {
        let available = UIApplication.shared.isProtectedDataAvailable
        cachedSystemAvailable.withLock { $0 = available }
    }
    #endif

    /// For testing only. `nil` means read the real UIKit state.
    public func setOverride(_ state: ProtectedDataState?) {
        overrideState.withLock { $0 = state }
    }

    public var state: ProtectedDataState {
        if let override = overrideState.withLock({ $0 }) { return override }
        return Self.systemState(self)
    }

    public var isAvailable: Bool {
        switch state {
        case .available:
            return true
        case .unavailable:
            return false
        }
    }

    #if canImport(UIKit)
    private static func systemState(_ monitor: ProtectedDataMonitor) -> ProtectedDataState {
        // On the main thread, read UIKit directly (safe and authoritative).
        if Thread.isMainThread {
            return UIApplication.shared.isProtectedDataAvailable
                ? .available
                : .unavailable(reason: "UIApplication.shared.isProtectedDataAvailable is false")
        }
        // Off the main thread, use the cached value. `nil` means we have not yet
        // observed a protectedDataAvailableDidChange notification — treat as
        // unavailable so background work defers until the cache is populated, rather
        // than risking a DispatchQueue.main.sync deadlock under Swift Concurrency.
        if let cached = monitor.cachedSystemAvailable.withLock({ $0 }) {
            return cached
                ? .available
                : .unavailable(reason: "cached UIApplication.shared.isProtectedDataAvailable is false")
        }
        return .unavailable(reason: "protected data availability unknown until first notification")
    }
    #else
    private static func systemState(_ monitor: ProtectedDataMonitor) -> ProtectedDataState {
        // SwiftPM tests run without UIKit; treat protected data as available so
        // database work is not silently skipped. On iOS, the real UIKit state is used.
        return .available
    }
    #endif

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
