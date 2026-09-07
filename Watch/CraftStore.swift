import Foundation
import SwiftUI
import WatchKit
import WidgetKit

/// App model for the Watch. Owns the MCP client, today's tasks, and the offline queue.
@Observable
final class CraftStore {
    static let shared = CraftStore()

    enum Status: Equatable {
        case disconnected
        case idle
        case working
        case saved(String)
        case failed(String)
    }

    private(set) var tasks: [CraftTask] = []
    private(set) var isConnected = false
    private(set) var spaceName: String?
    private(set) var pendingCount = 0
    private(set) var lastRefresh: Date?
    var status: Status = .idle

    /// Set by `CaptureToCraftIntent` (Action button) and the complication; the root
    /// view watches it and presents dictation. A fresh id each time so two presses in a
    /// row both register.
    private(set) var captureRequestID: UUID?

    var destination: CraftAPI.Destination {
        didSet { UserDefaults.standard.set(destination.rawValue, forKey: Self.destinationKey) }
    }

    private static let destinationKey = "defaultDestination"

    private let client = CraftMCPClient()
    private let queue = PendingQueue()
    private var api: CraftAPI { CraftAPI(client: client) }

    private init() {
        let stored = UserDefaults.standard.string(forKey: Self.destinationKey)
        destination = stored.flatMap(CraftAPI.Destination.init(rawValue:)) ?? .task
    }

    func requestCapture() {
        captureRequestID = UUID()
    }

    func clearCaptureRequest() {
        captureRequestID = nil
    }

    // MARK: - Lifecycle

    func bootstrap() async {
        isConnected = await client.isConnected
        spaceName = await client.spaceName
        pendingCount = await queue.count
        status = isConnected ? .idle : .disconnected
        guard isConnected else { return }
        await flushPending()
        await refresh()
    }

    /// Called when the iPhone hands over a freshly authorized Craft connection.
    func adopt(_ credentials: CraftCredentials) async {
        do {
            try await client.adopt(credentials)
            isConnected = true
            spaceName = credentials.spaceName
            status = .idle
            WKInterfaceDevice.current().play(.success)
            await flushPending()
            await refresh()
        } catch {
            status = .failed(error.localizedDescription)
        }
    }

    func disconnect() async {
        await client.disconnect()
        await queue.removeAll()
        isConnected = false
        spaceName = nil
        tasks = []
        pendingCount = 0
        status = .disconnected
        SharedDefaults.openTaskCount = nil
        WidgetCenter.shared.reloadAllTimelines()
    }

    /// Minimal state load for an App Intent running without the UI: enough to know
    /// whether there is a connection, without the cost of a full refresh.
    func prepare() async {
        isConnected = await client.isConnected
        spaceName = await client.spaceName
        pendingCount = await queue.count
    }

    // MARK: - Reads

    func refresh() async {
        guard isConnected else { return }
        status = .working
        do {
            let fetched = try await api.activeTasks()
            tasks = fetched.sorted { lhs, rhs in
                (lhs.taskDate ?? .distantFuture) < (rhs.taskDate ?? .distantFuture)
            }
            lastRefresh = Date()
            status = .idle
            publishToComplication()
        } catch {
            status = .failed(Self.message(for: error))
            if case CraftError.notConnected = error { isConnected = false }
        }
    }

    // MARK: - Writes

    /// Captures dictated text. Anything that cannot be sent right now is queued, so the
    /// user always gets a confirmation rather than losing what they said.
    func capture(_ raw: String, to explicitTarget: CraftAPI.Destination? = nil) async {
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }

        status = .working
        let target = explicitTarget ?? destination

        // Resolve any spoken due date here, not at send time: a capture that says
        // "tomorrow" and gets flushed from the queue next week must still mean the day
        // the speaker meant.
        var outgoing = text
        var scheduleDay: String?
        var confirmation = target == .task ? "Task saved" : "Added to Daily Note"

        if target == .task, let phrase = DatePhraseParser.parse(text) {
            outgoing = DatePhraseParser.taskText(for: phrase)
            scheduleDay = DatePhraseParser.craftDay(for: phrase.date)
            confirmation = "Saved for \(Self.dueLabel(for: phrase))"
        }

        do {
            try await api.capture(outgoing, to: target, scheduleDay: scheduleDay)
            WKInterfaceDevice.current().play(.success)
            status = .saved(confirmation)
            await refresh()
        } catch {
            await queue.enqueue(
                PendingCapture(text: outgoing, destination: target, scheduleDay: scheduleDay)
            )
            pendingCount = await queue.count
            WKInterfaceDevice.current().play(.notification)
            status = .saved("Queued — will send when connected")
            if case CraftError.notConnected = error { isConnected = false }
        }
    }

    func complete(_ task: CraftTask) async {
        guard isConnected else { return }
        // Optimistic removal: the row disappears the moment you tap it.
        let snapshot = tasks
        tasks.removeAll { $0.id == task.id }
        publishToComplication()

        do {
            try await api.complete(taskID: task.id)
            WKInterfaceDevice.current().play(.success)
        } catch {
            tasks = snapshot
            publishToComplication()
            WKInterfaceDevice.current().play(.failure)
            status = .failed(Self.message(for: error))
        }
    }

    func flushPending() async {
        guard isConnected, await queue.count > 0 else { return }
        let delivered = await queue.flush(using: api)
        pendingCount = await queue.count
        if delivered > 0 {
            status = .saved("Sent \(delivered) queued \(delivered == 1 ? "capture" : "captures")")
        }
    }

    // MARK: - Helpers

    private func publishToComplication() {
        SharedDefaults.openTaskCount = tasks.count
        WidgetCenter.shared.reloadAllTimelines()
    }

#if DEBUG
    /// Populates a plausible connected state so the main screen can be inspected in the
    /// simulator without a real Craft grant. Enabled with the CRAFT_DEMO=1 environment
    /// variable; never reachable in a release build.
    func seedDemo() {
        isConnected = true
        spaceName = "Danny\u{2019}s Space"
        lastRefresh = Date()
        status = .idle
        pendingCount = 0
        let day = Calendar.current.startOfDay(for: Date())
        tasks = [
            CraftTask(
                id: "demo-1",
                text: "Pull out ice machine to repair",
                isDone: false,
                scheduled: day.addingTimeInterval(-6 * 86_400),
                deadline: nil,
                container: "Home To Do List"
            ),
            CraftTask(
                id: "demo-2",
                text: "Get started on the will and trust",
                isDone: false,
                scheduled: day.addingTimeInterval(-4 * 86_400),
                deadline: nil,
                container: "inbox"
            ),
            CraftTask(
                id: "demo-3",
                text: "Review Millie release notes",
                isDone: false,
                scheduled: day,
                deadline: nil,
                container: "Planning"
            ),
        ]
    }
#endif

    /// Short enough for a watch face: "tomorrow", "Fri", or either plus the time.
    private static func dueLabel(for phrase: DatePhrase) -> String {
        let calendar = Calendar.current
        let day: String
        if calendar.isDateInToday(phrase.date) {
            day = "today"
        } else if calendar.isDateInTomorrow(phrase.date) {
            day = "tomorrow"
        } else {
            day = phrase.date.formatted(.dateTime.weekday(.abbreviated))
        }

        guard phrase.hasTime, !phrase.usedFallbackTitle else { return day }
        return "\(day) \(DatePhraseParser.timeLabel(for: phrase.date))"
    }

    private static func message(for error: Error) -> String {
        (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
    }
}
