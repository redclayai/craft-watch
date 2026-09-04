import Foundation

/// Everything the Watch needs to talk to Craft on its own, with no phone nearby.
///
/// The phone performs the one-time OAuth dance and hands this over. From then on the
/// Watch mints its own access tokens from `refreshToken`, which is what lets capture
/// work while the iPhone is locked or out of range.
nonisolated struct CraftCredentials: Codable, Sendable, Equatable {
    var clientID: String
    var refreshToken: String
    var accessToken: String?
    var accessTokenExpiry: Date?
    var resource: URL
    var tokenEndpoint: URL
    var spaceName: String?
    var connectedAt: Date

    var isAccessTokenFresh: Bool {
        guard accessToken != nil, let expiry = accessTokenExpiry else { return false }
        // Refresh a little early so a call never dies mid-flight.
        return expiry.timeIntervalSinceNow > 60
    }
}

nonisolated enum CraftEndpoint {
    static let resource = URL(string: "https://mcp.craft.do/my/mcp")!
    static let redirectURI = "craftwatch://oauth"
    static let clientName = "Craft Watch"
    static let appGroup = "group.ai.redclay.craftwatch"
}
