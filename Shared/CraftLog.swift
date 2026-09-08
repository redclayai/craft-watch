import Foundation
import OSLog

/// Logging for the paths that fail invisibly on a wrist: OAuth refresh, MCP transport,
/// capture, and the phone handoff.
///
/// Read it back with:
///
///     xcrun devicectl device process launch --device <udid> --console <bundle-id>
///
/// or in Console.app filtered on subsystem `ai.redclay.craftwatch`.
nonisolated enum CraftLog {
    private static let subsystem = "ai.redclay.craftwatch"

    static let oauth = Logger(subsystem: subsystem, category: "oauth")
    static let mcp = Logger(subsystem: subsystem, category: "mcp")
    static let capture = Logger(subsystem: subsystem, category: "capture")
    static let handoff = Logger(subsystem: subsystem, category: "handoff")
}
