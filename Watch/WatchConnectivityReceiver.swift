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
            await CraftStore.shared.adopt(credentials)
        }
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
