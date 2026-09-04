import AuthenticationServices
import Foundation
import SwiftUI

/// The iPhone side exists for one job: run the OAuth flow once and hand the resulting
/// credentials to the Watch. It deliberately does not call Craft afterwards, so the Watch
/// is the only device rotating the refresh token.
@Observable
final class SetupModel {

    enum State: Equatable {
        case idle
        case connecting
        case connected(space: String?)
        case failed(String)
    }

    private(set) var state: State = .idle

    private let oauth = CraftOAuth()
    private let store = CredentialStore.shared
    private let connectivity = PhoneConnectivity.shared
    private var presenter = AuthPresentationAnchor()

    /// Kicks off session activation. Watch availability and delivery status are read from
    /// `PhoneConnectivity` by the view as they arrive, since activation is asynchronous.
    func load() {
        connectivity.activate()
        if let existing = store.load() {
            state = .connected(space: existing.spaceName)
            // Re-offer the handoff in case a previous attempt predated activation.
            connectivity.send(existing)
        }
    }

    func connect() async {
        state = .connecting
        do {
            let pending = try await oauth.beginAuthorization()
            let callback = try await authorize(url: pending.url)
            var credentials = try await oauth.exchange(callback: callback, pending: pending)

            // Confirm the grant actually works, and pick up the space name for the UI.
            credentials.spaceName = try? await verifiedSpaceName(for: credentials)

            try store.save(credentials)
            connectivity.send(credentials)
            state = .connected(space: credentials.spaceName)
        } catch is CancellationError {
            state = .idle
        } catch let error as ASWebAuthenticationSessionError where error.code == .canceledLogin {
            state = .idle
        } catch {
            state = .failed((error as? LocalizedError)?.errorDescription ?? error.localizedDescription)
        }
    }

    func resend() {
        guard let credentials = store.load() else { return }
        connectivity.send(credentials)
        state = .connected(space: credentials.spaceName)
    }

    func reset() {
        store.clear()
        connectivity.clear()
        state = .idle
    }

    // MARK: - Helpers

    private func verifiedSpaceName(for credentials: CraftCredentials) async throws -> String? {
        let client = CraftMCPClient()
        try await client.adopt(credentials)
        let name = try await CraftAPI(client: client).connectionSpaceName()
        // The phone must not hold a live session; the Watch owns the connection.
        await client.disconnect()
        return name
    }

    private func authorize(url: URL) async throws -> URL {
        let anchor = presenter
        return try await withCheckedThrowingContinuation { continuation in
            let session = ASWebAuthenticationSession(
                url: url,
                callbackURLScheme: "craftwatch"
            ) { callback, error in
                if let callback {
                    continuation.resume(returning: callback)
                } else {
                    continuation.resume(throwing: error ?? CraftError.oauth("Sign-in was dismissed"))
                }
            }
            session.presentationContextProvider = anchor
            session.prefersEphemeralWebBrowserSession = false
            session.start()
        }
    }
}

private final class AuthPresentationAnchor: NSObject, ASWebAuthenticationPresentationContextProviding {
    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        UIApplication.shared.connectedScenes
            .compactMap { ($0 as? UIWindowScene)?.keyWindow }
            .first ?? ASPresentationAnchor()
    }
}
