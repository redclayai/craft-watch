import Foundation
import WatchConnectivity

/// Hands credentials to the Watch. Application context is used because it is durable:
/// if the Watch is asleep or out of range, WatchConnectivity delivers it later without
/// the phone having to retry.
final class PhoneConnectivity: NSObject, WCSessionDelegate {
    static let shared = PhoneConnectivity()

    private override init() { super.init() }

    private(set) var hasDeliveredCredentials = false

    var isWatchAppAvailable: Bool {
        guard WCSession.isSupported() else { return false }
        let session = WCSession.default
        return session.isPaired && session.isWatchAppInstalled
    }

    func activate() {
        guard WCSession.isSupported() else { return }
        let session = WCSession.default
        session.delegate = self
        session.activate()
        hasDeliveredCredentials = session.applicationContext["credentials"] != nil
    }

    @discardableResult
    func send(_ credentials: CraftCredentials) -> Bool {
        guard WCSession.isSupported(), let data = try? JSONEncoder().encode(credentials) else { return false }
        let session = WCSession.default
        do {
            try session.updateApplicationContext(["credentials": data, "updatedAt": Date().timeIntervalSince1970])
            hasDeliveredCredentials = true
            // Also nudge it as user info so a running Watch app picks it up immediately.
            session.transferUserInfo(["credentials": data])
            return true
        } catch {
            return false
        }
    }

    func clear() {
        hasDeliveredCredentials = false
        guard WCSession.isSupported() else { return }
        try? WCSession.default.updateApplicationContext([:])
    }

    // MARK: - WCSessionDelegate

    nonisolated func session(
        _ session: WCSession,
        activationDidCompleteWith state: WCSessionActivationState,
        error: Error?
    ) {}

    nonisolated func sessionDidBecomeInactive(_ session: WCSession) {}

    nonisolated func sessionDidDeactivate(_ session: WCSession) {
        WCSession.default.activate()
    }
}
