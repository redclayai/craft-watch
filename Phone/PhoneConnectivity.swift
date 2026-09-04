import Foundation
import WatchConnectivity

/// Hands credentials to the Watch.
///
/// `WCSession.activate()` completes asynchronously, and every interesting property —
/// `isPaired`, `isWatchAppInstalled`, `applicationContext`, `updateApplicationContext` —
/// is invalid until it has. So nothing is read eagerly: state is published from the
/// activation callback and from `sessionWatchStateDidChange`, and a handoff issued before
/// activation is held and delivered once the session is up.
///
/// Application context is the transport because it is durable: if the Watch is asleep or
/// out of range, WatchConnectivity delivers it later without the phone retrying.
@Observable
final class PhoneConnectivity: NSObject, WCSessionDelegate {
    static let shared = PhoneConnectivity()

    private(set) var isActivated = false
    private(set) var isWatchAppAvailable = false
    private(set) var hasDeliveredCredentials = false

    private var queuedCredentials: CraftCredentials?

    private override init() { super.init() }

    var isSupported: Bool { WCSession.isSupported() }

    func activate() {
        guard WCSession.isSupported() else { return }
        let session = WCSession.default
        session.delegate = self
        session.activate()
    }

    /// Returns whether the handoff went out now. `false` means it was held until the
    /// session activates, not that it failed.
    @discardableResult
    func send(_ credentials: CraftCredentials) -> Bool {
        guard WCSession.isSupported() else { return false }
        guard isActivated else {
            queuedCredentials = credentials
            return false
        }
        return deliver(credentials)
    }

    func clear() {
        queuedCredentials = nil
        hasDeliveredCredentials = false
        guard WCSession.isSupported(), isActivated else { return }
        try? WCSession.default.updateApplicationContext([:])
    }

    // MARK: - Delivery

    private func deliver(_ credentials: CraftCredentials) -> Bool {
        guard let data = try? JSONEncoder().encode(credentials) else { return false }
        let session = WCSession.default
        do {
            try session.updateApplicationContext([
                "credentials": data,
                "updatedAt": Date().timeIntervalSince1970,
            ])
            hasDeliveredCredentials = true
            // Also nudge it as user info so a running Watch app picks it up immediately.
            if session.isWatchAppInstalled {
                session.transferUserInfo(["credentials": data])
            }
            return true
        } catch {
            return false
        }
    }

    private func refreshState() {
        let session = WCSession.default
        isActivated = session.activationState == .activated
        guard isActivated else {
            isWatchAppAvailable = false
            return
        }
        isWatchAppAvailable = session.isPaired && session.isWatchAppInstalled
        if session.applicationContext["credentials"] != nil {
            hasDeliveredCredentials = true
        }
        if let queued = queuedCredentials, deliver(queued) {
            queuedCredentials = nil
        }
    }

    // MARK: - WCSessionDelegate

    nonisolated func session(
        _ session: WCSession,
        activationDidCompleteWith state: WCSessionActivationState,
        error: Error?
    ) {
        Task { @MainActor in self.refreshState() }
    }

    nonisolated func sessionWatchStateDidChange(_ session: WCSession) {
        Task { @MainActor in self.refreshState() }
    }

    nonisolated func sessionDidBecomeInactive(_ session: WCSession) {}

    nonisolated func sessionDidDeactivate(_ session: WCSession) {
        // Reactivate so a switch to a different paired Watch keeps working.
        WCSession.default.activate()
        Task { @MainActor in self.refreshState() }
    }
}
