import Foundation
import WatchConnectivity

/// Receives the Craft credentials the iPhone hands over after its one-time OAuth flow.
///
/// Application context is used rather than a message so the handoff still lands if the
/// Watch app was not running at the time.
final class WatchConnectivityReceiver: NSObject, WCSessionDelegate {
    static let shared = WatchConnectivityReceiver()

    private override init() { super.init() }

    func activate() {
        guard WCSession.isSupported() else { return }
        let session = WCSession.default
        session.delegate = self
        session.activate()
        ingest(session.receivedApplicationContext)
    }

    nonisolated private func ingest(_ payload: [String: Any]) {
        guard let data = payload["credentials"] as? Data,
              let credentials = try? JSONDecoder().decode(CraftCredentials.self, from: data)
        else { return }

        Task { @MainActor in
            let store = CraftStore.shared
            await store.adopt(credentials)
            // The phone cannot tell whether application context actually landed, so
            // confirm explicitly. Without this it reports "sent" on faith.
            if store.isConnected { Self.acknowledge() }
        }
    }

    /// Tells the phone the credentials arrived and were stored.
    nonisolated private static func acknowledge() {
        guard WCSession.isSupported() else { return }
        let session = WCSession.default
        guard session.activationState == .activated else { return }
        session.transferUserInfo(["credentialsAck": true])
    }

    // MARK: - WCSessionDelegate

    nonisolated func session(
        _ session: WCSession,
        activationDidCompleteWith state: WCSessionActivationState,
        error: Error?
    ) {
        guard state == .activated else { return }
        ingest(session.receivedApplicationContext)
    }

    nonisolated func session(_ session: WCSession, didReceiveApplicationContext context: [String: Any]) {
        ingest(context)
    }

    nonisolated func session(_ session: WCSession, didReceiveUserInfo userInfo: [String: Any]) {
        ingest(userInfo)
    }

    nonisolated func session(
        _ session: WCSession,
        didReceiveMessage message: [String: Any],
        replyHandler: @escaping ([String: Any]) -> Void
    ) {
        ingest(message)
        replyHandler(["received": true])
    }
}
