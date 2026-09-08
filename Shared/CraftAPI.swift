import Foundation

/// The four operations the Watch app actually performs, expressed as Craft CLI commands.
nonisolated struct CraftAPI: Sendable {

    nonisolated enum Destination: String, Codable, Sendable, CaseIterable, Identifiable {
        case task
        case dailyNote

        var id: String { rawValue }

        var label: String {
            switch self {
            case .task: "Task"
            case .dailyNote: "Daily Note"
            }
        }

        var symbol: String {
            switch self {
            case .task: "checklist"
            case .dailyNote: "sun.max"
            }
        }
    }

    let client: CraftMCPClient

    // MARK: - Reads

    func activeTasks() async throws -> [CraftTask] {
        let output = try await client.read("tasks list --scope active")
        return TaskListParser.parse(output).filter { !$0.isDone }
    }

    func connectionSpaceName() async throws -> String? {
        struct Info: Decodable { struct Space: Decodable { let name: String? }; let space: Space? }
        let output = try await client.read("connection info")
        guard let data = output.data(using: .utf8),
              let info = try? JSONDecoder().decode(Info.self, from: data) else { return nil }
        return info.space?.name
    }

    // MARK: - Writes

    /// `scheduleDay` is `YYYY-MM-DD`; omitting it schedules today.
    ///
    /// Craft stores only a date — `taskInfo.scheduleDate` has no time component, and a
    /// time passed here is silently dropped — so any spoken clock time is carried in the
    /// task text instead.
    func addTask(_ text: String, scheduleDay: String? = nil) async throws {
        let day = scheduleDay ?? "today"
        try await runWrite("tasks add --markdown \(Self.quote(text)) --schedule \(Self.quote(day))")
    }

    func complete(taskID: String) async throws {
        try await runWrite("tasks update --id \(Self.quote(taskID)) --state done")
    }

    /// Appends to a Daily Note, creating it if that day has none yet.
    ///
    /// `blocks add --date` is undocumented but does both, which matters: looking the page
    /// up first with `blocks get --date today` fails outright on any day whose note does
    /// not exist yet — which is most mornings — and there is no page id to append to.
    func appendToDailyNote(_ text: String, day: String = "today") async throws {
        try await runWrite("blocks add --date \(Self.quote(day)) --markdown \(Self.quote(text)) --position end")
    }

    func capture(_ text: String, to destination: Destination, scheduleDay: String? = nil) async throws {
        switch destination {
        case .task: try await addTask(text, scheduleDay: scheduleDay)
        case .dailyNote: try await appendToDailyNote(text)
        }
    }

    // MARK: - Helpers

    /// Craft's write commands answer with `{"success": …}`; surface a failure rather than
    /// letting a silent no-op look like a save.
    private func runWrite(_ command: String) async throws {
        let output = try await client.write(command)
        guard let data = output.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return }

        if let success = object["success"] as? Bool, !success {
            let message = object["error"] as? String ?? object["message"] as? String ?? "Craft rejected the change"
            throw CraftError.rpc(code: -1, message: message)
        }
    }

    /// The command string is parsed shell-style, so arguments need double quoting with
    /// backslashes and inner quotes escaped.
    static func quote(_ value: String) -> String {
        let escaped = value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "\n", with: " ")
        return "\"\(escaped)\""
    }
}
