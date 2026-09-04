import Foundation

nonisolated enum CraftError: LocalizedError, Sendable {
    case notConnected
    case http(status: Int, body: String)
    case oauth(String)
    case rpc(code: Int, message: String)
    case toolUnavailable(String)
    case malformedResponse(String)
    case keychain(OSStatus)
    case offline

    var errorDescription: String? {
        switch self {
        case .notConnected:
            "Not connected to Craft. Open Craft Watch on your iPhone to connect."
        case let .http(status, body):
            "Craft returned HTTP \(status). \(body.prefix(200))"
        case let .oauth(detail):
            "Sign-in failed: \(detail)"
        case let .rpc(code, message):
            "Craft error \(code): \(message)"
        case let .toolUnavailable(name):
            "Craft did not offer the \(name) tool."
        case let .malformedResponse(detail):
            "Unexpected response from Craft: \(detail)"
        case let .keychain(status):
            "Keychain error \(status)."
        case .offline:
            "No connection. Saved to send later."
        }
    }

    /// Worth retrying later from the offline queue, as opposed to a hard failure.
    var isTransient: Bool {
        switch self {
        case .offline: true
        case let .http(status, _): status == 429 || status >= 500
        default: false
        }
    }
}
