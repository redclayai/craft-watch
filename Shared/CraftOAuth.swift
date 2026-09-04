import CryptoKit
import Foundation

/// OAuth 2.1 for the Craft MCP server: RFC 9728 resource discovery, RFC 7591 dynamic
/// client registration, PKCE, and RFC 8707 resource indicators.
///
/// Craft advertises `token_endpoint_auth_methods_supported: ["none"]`, so this is a
/// public client — there is no secret to hide in the app bundle.
nonisolated struct CraftOAuth: Sendable {

    nonisolated struct Metadata: Sendable {
        var authorizationEndpoint: URL
        var tokenEndpoint: URL
        var registrationEndpoint: URL?
    }

    nonisolated struct PendingAuthorization: Sendable {
        var url: URL
        var clientID: String
        var codeVerifier: String
        var state: String
        var metadata: Metadata
    }

    private let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    // MARK: - Discovery

    /// Walks the discovery chain: protected-resource metadata names the authorization
    /// server, whose own metadata gives us the endpoints.
    func discover(resource: URL = CraftEndpoint.resource) async throws -> Metadata {
        let issuer = try await authorizationServer(for: resource)
        return try await metadata(forIssuer: issuer)
    }

    private func authorizationServer(for resource: URL) async throws -> URL {
        guard var components = URLComponents(url: resource, resolvingAgainstBaseURL: false) else {
            throw CraftError.oauth("Bad resource URL")
        }
        let path = components.path
        components.path = "/.well-known/oauth-protected-resource" + path
        guard let url = components.url else { throw CraftError.oauth("Bad discovery URL") }

        struct ProtectedResource: Decodable { let authorization_servers: [URL]? }
        let payload: ProtectedResource = try await getJSON(url)
        guard let issuer = payload.authorization_servers?.first else {
            throw CraftError.oauth("Craft did not advertise an authorization server")
        }
        return issuer
    }

    private func metadata(forIssuer issuer: URL) async throws -> Metadata {
        struct Payload: Decodable {
            let authorization_endpoint: URL
            let token_endpoint: URL
            let registration_endpoint: URL?
        }

        // RFC 8414 inserts the well-known segment before the issuer path; some servers
        // instead append it. Try both before giving up.
        var candidates: [URL] = []
        if var components = URLComponents(url: issuer, resolvingAgainstBaseURL: false) {
            let issuerPath = components.path
            components.path = "/.well-known/oauth-authorization-server" + issuerPath
            if let url = components.url { candidates.append(url) }
        }
        candidates.append(issuer.appendingPathComponent(".well-known/oauth-authorization-server"))
        candidates.append(issuer.appendingPathComponent(".well-known/openid-configuration"))

        var lastError: Error = CraftError.oauth("No authorization server metadata")
        for candidate in candidates {
            do {
                let payload: Payload = try await getJSON(candidate)
                return Metadata(
                    authorizationEndpoint: payload.authorization_endpoint,
                    tokenEndpoint: payload.token_endpoint,
                    registrationEndpoint: payload.registration_endpoint
                )
            } catch {
                lastError = error
            }
        }
        throw lastError
    }

    // MARK: - Registration

    func register(at endpoint: URL) async throws -> String {
        struct Response: Decodable { let client_id: String }
        let body: [String: Any] = [
            "client_name": CraftEndpoint.clientName,
            "redirect_uris": [CraftEndpoint.redirectURI],
            "grant_types": ["authorization_code", "refresh_token"],
            "response_types": ["code"],
            "token_endpoint_auth_method": "none",
            "application_type": "native",
        ]
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        let response: Response = try await decode(request)
        return response.client_id
    }

    // MARK: - Authorization request

    func beginAuthorization(resource: URL = CraftEndpoint.resource) async throws -> PendingAuthorization {
        let metadata = try await discover(resource: resource)
        guard let registration = metadata.registrationEndpoint else {
            throw CraftError.oauth("Craft does not support dynamic client registration")
        }
        let clientID = try await register(at: registration)

        let verifier = Self.randomURLSafeString(byteCount: 64)
        let challenge = Self.codeChallenge(for: verifier)
        let state = Self.randomURLSafeString(byteCount: 32)

        guard var components = URLComponents(url: metadata.authorizationEndpoint, resolvingAgainstBaseURL: false) else {
            throw CraftError.oauth("Bad authorization endpoint")
        }
        components.queryItems = [
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "client_id", value: clientID),
            URLQueryItem(name: "redirect_uri", value: CraftEndpoint.redirectURI),
            URLQueryItem(name: "code_challenge", value: challenge),
            URLQueryItem(name: "code_challenge_method", value: "S256"),
            URLQueryItem(name: "state", value: state),
            URLQueryItem(name: "resource", value: resource.absoluteString),
        ]
        guard let url = components.url else { throw CraftError.oauth("Bad authorization URL") }

        return PendingAuthorization(
            url: url,
            clientID: clientID,
            codeVerifier: verifier,
            state: state,
            metadata: metadata
        )
    }

    // MARK: - Token exchange

    nonisolated struct TokenResponse: Decodable, Sendable {
        let access_token: String
        let refresh_token: String?
        let expires_in: Double?
    }

    func exchange(
        callback: URL,
        pending: PendingAuthorization,
        resource: URL = CraftEndpoint.resource
    ) async throws -> CraftCredentials {
        let items = URLComponents(url: callback, resolvingAgainstBaseURL: false)?.queryItems ?? []
        func value(_ name: String) -> String? { items.first { $0.name == name }?.value }

        if let error = value("error") {
            throw CraftError.oauth(value("error_description") ?? error)
        }
        guard let code = value("code") else { throw CraftError.oauth("No authorization code returned") }
        guard value("state") == pending.state else { throw CraftError.oauth("State mismatch") }

        let token = try await postToken(
            to: pending.metadata.tokenEndpoint,
            fields: [
                "grant_type": "authorization_code",
                "code": code,
                "redirect_uri": CraftEndpoint.redirectURI,
                "client_id": pending.clientID,
                "code_verifier": pending.codeVerifier,
                "resource": resource.absoluteString,
            ]
        )

        guard let refresh = token.refresh_token else {
            throw CraftError.oauth("Craft did not issue a refresh token, so the Watch could not stay signed in")
        }

        return CraftCredentials(
            clientID: pending.clientID,
            refreshToken: refresh,
            accessToken: token.access_token,
            accessTokenExpiry: token.expires_in.map { Date(timeIntervalSinceNow: $0) },
            resource: resource,
            tokenEndpoint: pending.metadata.tokenEndpoint,
            spaceName: nil,
            connectedAt: Date()
        )
    }

    /// Mints a fresh access token. Called from the Watch, with no phone in the loop.
    func refresh(_ credentials: CraftCredentials) async throws -> CraftCredentials {
        let token = try await postToken(
            to: credentials.tokenEndpoint,
            fields: [
                "grant_type": "refresh_token",
                "refresh_token": credentials.refreshToken,
                "client_id": credentials.clientID,
                "resource": credentials.resource.absoluteString,
            ]
        )
        var updated = credentials
        updated.accessToken = token.access_token
        updated.accessTokenExpiry = token.expires_in.map { Date(timeIntervalSinceNow: $0) }
        // Craft may rotate the refresh token; keep whichever one is current.
        if let rotated = token.refresh_token { updated.refreshToken = rotated }
        return updated
    }

    private func postToken(to endpoint: URL, fields: [String: String]) async throws -> TokenResponse {
        var components = URLComponents()
        components.queryItems = fields.map { URLQueryItem(name: $0.key, value: $0.value) }
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.httpBody = components.percentEncodedQuery?.data(using: .utf8)
        return try await decode(request)
    }

    // MARK: - Plumbing

    private func getJSON<T: Decodable>(_ url: URL) async throws -> T {
        var request = URLRequest(url: url)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        return try await decode(request)
    }

    private func decode<T: Decodable>(_ request: URLRequest) async throws -> T {
        let (data, response) = try await session.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200 ..< 300).contains(status) else {
            throw CraftError.http(status: status, body: String(decoding: data, as: UTF8.self))
        }
        do {
            return try JSONDecoder().decode(T.self, from: data)
        } catch {
            throw CraftError.malformedResponse(String(decoding: data.prefix(200), as: UTF8.self))
        }
    }

    // MARK: - PKCE

    static func randomURLSafeString(byteCount: Int) -> String {
        var bytes = [UInt8](repeating: 0, count: byteCount)
        _ = SecRandomCopyBytes(kSecRandomDefault, byteCount, &bytes)
        return Data(bytes).base64URLEncodedString()
    }

    static func codeChallenge(for verifier: String) -> String {
        let digest = SHA256.hash(data: Data(verifier.utf8))
        return Data(digest).base64URLEncodedString()
    }
}

nonisolated extension Data {
    func base64URLEncodedString() -> String {
        base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}
