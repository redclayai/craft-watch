import Foundation

/// A minimal MCP client for Craft, speaking JSON-RPC over the Streamable HTTP transport.
///
/// Craft's whole surface is two tools that each take a single CLI-style `command` string,
/// so there is nothing here worth pulling in a dependency for. Everything runs on
/// `URLSession`, which is exactly what lets it work on watchOS with no phone attached.
actor CraftMCPClient {

    private let protocolVersion = "2025-06-18"
    private let session: URLSession
    private let oauth: CraftOAuth
    private let store: CredentialStore

    private var credentials: CraftCredentials?
    private var mcpSessionID: String?
    private var discoveredTools: [String] = []
    private var nextRequestID = 1

    init(
        session: URLSession = .craftDefault,
        oauth: CraftOAuth = CraftOAuth(),
        store: CredentialStore = .shared
    ) {
        self.session = session
        self.oauth = oauth
        self.store = store
        credentials = store.load()
    }

    // MARK: - Connection state

    var isConnected: Bool { credentials != nil }

    var spaceName: String? { credentials?.spaceName }

    func adopt(_ credentials: CraftCredentials) throws {
        try store.save(credentials)
        self.credentials = credentials
        mcpSessionID = nil
        discoveredTools = []
    }

    func reloadCredentials() {
        credentials = store.load()
        mcpSessionID = nil
        discoveredTools = []
    }

    func disconnect() {
        store.clear()
        credentials = nil
        mcpSessionID = nil
        discoveredTools = []
    }

    // MARK: - Craft operations

    /// Runs a `craft_read` command, e.g. `tasks list --scope active`.
    func read(_ command: String) async throws -> String {
        try await callTool(matching: ["craft_read", "read"], command: command)
    }

    /// Runs a `craft_write` command, e.g. `tasks add --markdown "Call Ryan"`.
    func write(_ command: String) async throws -> String {
        try await callTool(matching: ["craft_write", "write"], command: command)
    }

    // MARK: - Tool dispatch

    private func callTool(matching candidates: [String], command: String) async throws -> String {
        let name = try await resolveToolName(candidates: candidates)
        let result = try await request(
            method: "tools/call",
            params: ["name": name, "arguments": ["command": command]]
        )

        if let isError = result["isError"] as? Bool, isError {
            throw CraftError.rpc(code: -1, message: Self.textContent(of: result))
        }
        return Self.textContent(of: result)
    }

    /// Craft's tool names are stable, but resolving them from `tools/list` means a rename
    /// on their side degrades to a clear error instead of a silent 404.
    private func resolveToolName(candidates: [String]) async throws -> String {
        if discoveredTools.isEmpty {
            let result = try await request(method: "tools/list", params: [:])
            let tools = result["tools"] as? [[String: Any]] ?? []
            discoveredTools = tools.compactMap { $0["name"] as? String }
        }
        if let exact = candidates.first(where: { discoveredTools.contains($0) }) {
            return exact
        }
        // Fall back to a suffix match so a namespaced name still resolves.
        for candidate in candidates {
            if let match = discoveredTools.first(where: { $0.hasSuffix(candidate) }) {
                return match
            }
        }
        throw CraftError.toolUnavailable(candidates.joined(separator: " or "))
    }

    private static func textContent(of result: [String: Any]) -> String {
        let content = result["content"] as? [[String: Any]] ?? []
        return content
            .compactMap { $0["text"] as? String }
            .joined(separator: "\n")
    }

    // MARK: - JSON-RPC

    private func request(method: String, params: [String: Any]) async throws -> [String: Any] {
        try await ensureInitialized()
        return try await send(method: method, params: params, allowRetry: true)
    }

    private func ensureInitialized() async throws {
        guard mcpSessionID == nil else { return }

        let result = try await send(
            method: "initialize",
            params: [
                "protocolVersion": protocolVersion,
                "capabilities": [:],
                "clientInfo": ["name": CraftEndpoint.clientName, "version": "1.0"],
            ],
            allowRetry: true,
            isInitialize: true
        )
        _ = result
        try? await sendNotification(method: "notifications/initialized")
    }

    @discardableResult
    private func send(
        method: String,
        params: [String: Any],
        allowRetry: Bool,
        isInitialize: Bool = false
    ) async throws -> [String: Any] {
        let id = nextRequestID
        nextRequestID += 1

        let body: [String: Any] = [
            "jsonrpc": "2.0",
            "id": id,
            "method": method,
            "params": params,
        ]

        let (data, response) = try await perform(body: body)

        if isInitialize, let sessionID = response.value(forHTTPHeaderField: "Mcp-Session-Id") {
            mcpSessionID = sessionID
        }

        switch response.statusCode {
        case 200 ..< 300:
            break
        case 401:
            guard allowRetry else { throw CraftError.notConnected }
            try await refreshAccessToken(force: true)
            return try await send(method: method, params: params, allowRetry: false, isInitialize: isInitialize)
        case 404 where !isInitialize:
            // The server dropped our session; start a new one and replay once.
            guard allowRetry else { throw CraftError.http(status: 404, body: "Session expired") }
            mcpSessionID = nil
            discoveredTools = []
            try await ensureInitialized()
            return try await send(method: method, params: params, allowRetry: false)
        default:
            throw CraftError.http(status: response.statusCode, body: String(decoding: data, as: UTF8.self))
        }

        let envelope = try Self.jsonRPCPayload(from: data, contentType: response.value(forHTTPHeaderField: "Content-Type"))

        if let error = envelope["error"] as? [String: Any] {
            throw CraftError.rpc(
                code: error["code"] as? Int ?? -1,
                message: error["message"] as? String ?? "Unknown error"
            )
        }
        guard let result = envelope["result"] as? [String: Any] else {
            throw CraftError.malformedResponse("No result for \(method)")
        }
        return result
    }

    private func sendNotification(method: String) async throws {
        _ = try await perform(body: ["jsonrpc": "2.0", "method": method])
    }

    private func perform(body: [String: Any]) async throws -> (Data, HTTPURLResponse) {
        guard let credentials else { throw CraftError.notConnected }
        try await refreshAccessToken(force: false)
        guard let token = self.credentials?.accessToken else { throw CraftError.notConnected }

        var request = URLRequest(url: credentials.resource)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json, text/event-stream", forHTTPHeaderField: "Accept")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue(protocolVersion, forHTTPHeaderField: "MCP-Protocol-Version")
        if let mcpSessionID {
            request.setValue(mcpSessionID, forHTTPHeaderField: "Mcp-Session-Id")
        }
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        do {
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse else {
                throw CraftError.malformedResponse("Not an HTTP response")
            }
            return (data, http)
        } catch let error as URLError {
            switch error.code {
            case .notConnectedToInternet, .networkConnectionLost, .timedOut,
                 .cannotConnectToHost, .cannotFindHost, .dataNotAllowed, .internationalRoamingOff:
                throw CraftError.offline
            default:
                throw error
            }
        }
    }

    private func refreshAccessToken(force: Bool) async throws {
        guard let current = credentials else { throw CraftError.notConnected }
        if !force, current.isAccessTokenFresh { return }

        let refreshed: CraftCredentials
        do {
            refreshed = try await oauth.refresh(current)
        } catch let error as CraftError {
            // Only an explicit `invalid_grant` justifies deleting the refresh token.
            // Token endpoints answer 400 for plenty of recoverable reasons, and treating
            // any of them as a sign-out loses the user's connection over a hiccup.
            if case let .grantExpired(detail) = error {
                CraftLog.oauth.error("Refresh token rejected as invalid_grant; signing out")
                SharedDefaults.lastSignOutReason =
                    "Craft rejected the saved sign-in. \(detail.prefix(120))"
                disconnect()
                throw error
            }
            CraftLog.oauth.error(
                "Token refresh failed, keeping credentials: \(error.localizedDescription, privacy: .public)"
            )
            throw error
        }
        try? store.save(refreshed)
        credentials = refreshed
    }

    // MARK: - Response parsing

    /// Streamable HTTP may answer with a plain JSON body or an SSE stream carrying one
    /// `message` event. Handle both rather than assuming.
    private static func jsonRPCPayload(from data: Data, contentType: String?) throws -> [String: Any] {
        if contentType?.contains("text/event-stream") == true {
            let text = String(decoding: data, as: UTF8.self)
            for line in text.split(separator: "\n", omittingEmptySubsequences: true) {
                guard line.hasPrefix("data:") else { continue }
                let payload = line.dropFirst(5).trimmingCharacters(in: .whitespaces)
                if let object = try? JSONSerialization.jsonObject(with: Data(payload.utf8)) as? [String: Any],
                   object["jsonrpc"] != nil {
                    return object
                }
            }
            throw CraftError.malformedResponse("No JSON-RPC message in event stream")
        }

        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw CraftError.malformedResponse(String(decoding: data.prefix(200), as: UTF8.self))
        }
        return object
    }
}

nonisolated extension URLSession {
    /// Short timeouts: on the wrist, a request that has not landed in 20 seconds should
    /// go to the offline queue rather than leave the user staring at a spinner.
    static let craftDefault: URLSession = {
        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = 20
        configuration.timeoutIntervalForResource = 45
        configuration.waitsForConnectivity = false
        return URLSession(configuration: configuration)
    }()
}
