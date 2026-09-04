import Foundation
import WatchConnectivity

/// Hands credentials to the Watch.
///
/// Two things about WatchConnectivity shape this class:
///
/// 1. `activate()` completes asynchronously, and `isPaired`, `isWatchAppInstalled`,
///    `applicationContext` and `updateApplicationContext` are all invalid until it has.
///    So nothing is read eagerly; state is published from the activation callback and
///    from `sessionWatchStateDidChange`.
/// 2. `updateApplicationContext` reports `WCErrorCodeWatchAppNotInstalled`
///    *asynchronously*, inside a completion block, without throwing. Treating a
///    non-throwing call as delivery therefore reports success for credentials the Watch
///    never received.
///
/// So credentials are held until the Watch explicitly acknowledges them, and delivery is
/// only attempted once the Watch app actually exists. Application context is the
/// transport because it is durable: once set, WatchConnectivity delivers it whenever the
/// Watch next becomes available.
@Observable
final class PhoneConnectivity: NSObject, WCSessionDelegate {
    static let shared = PhoneConnectivity()

    private(set) var isActivated = false
    private(set) var isWatchAppAvailable = false

    /// True only once the Watch has confirmed receipt.
    private(set) var hasDeliveredCredentials = false

    private var pendingCredentials: CraftCredentials?

    private override init() { super.init() }

    var isSupported: Bool { WCSession.isSupported() }

    /// Credentials are saved and waiting for a Watch that cannot take them yet.
    var isAwaitingWatch: Bool { pendingCredentials != nil && !hasDeliveredCredentials }

    func activate() {
        guard WCSession.isSupported() else { return }
        let session = WCSession.default
        session.delegate = self
        session.activate()
    }

    /// Returns whether the handoff went out now. `false` means it is held until the Watch
    /// app appears, not that it failed.
    @discardableResult
    func send(_ credentials: CraftCredentials) -> Bool {
        guard WCSession.isSupported() else { return false }
        pendingCredentials = credentials
        hasDeliveredCredentials = false
        return attemptDelivery()
    }

    func clear() {
        pendingCredentials = nil
        hasDeliveredCredentials = false
        guard WCSession.isSupported(), isActivated else { return }
        try? WCSession.default.updateApplicationContext([:])
    }

    // MARK: - Delivery

    @discardableResult
    private func attemptDelivery() -> Bool {
        guard let credentials = pendingCredentials, isActivated else { return false }

        let session = WCSession.default
        // Gate on the counterpart existing. Without this the call succeeds and then fails
        // in a block we never see.
        guard session.isPaired, session.isWatchAppInstalled else { return false }
        guard let data = try? JSONEncoder().encode(credentials) else { return false }

        do {
            try session.updateApplicationContext([
                "credentials": data,
                "updatedAt": Date().timeIntervalSince1970,
            ])
            // Nudge a running Watch app so it does not wait for the next context delivery.
            session.transferUserInfo(["credentials": data])
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
        // Installing the Watch app changes watch state, which lands here — the natural
        // point to deliver a handoff that had nowhere to go.
        attemptDelivery()
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

    nonisolated func session(_ session: WCSession, didReceiveUserInfo userInfo: [String: Any]) {
        guard userInfo["credentialsAck"] != nil else { return }
        Task { @MainActor in
            self.hasDeliveredCredentials = true
            self.pendingCredentials = nil
        }
    }

    nonisolated func sessionDidBecomeInactive(_ session: WCSession) {}

    nonisolated func sessionDidDeactivate(_ session: WCSession) {
        WCSession.default.activate()
        Task { @MainActor in self.refreshState() }
    }
}
