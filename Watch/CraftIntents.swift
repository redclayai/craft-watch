import AppIntents
import SwiftUI

/// App Intents, which is how the Action button reaches this app.
///
/// Apple reserves *direct* Action button registration (`StartWorkoutIntent`,
/// `StartDiveIntent`) for workout and dive apps, so a capture app cannot appear in
/// Settings ▸ Action Button ▸ App. It can be reached through the built-in
/// Action ▸ Shortcut option, which runs any intent exposed here.
///
/// Per Apple's guidance these live in the watchOS app target itself, never in an
/// App Intents extension.

/// One press: open the app straight into dictation.
struct CaptureToCraftIntent: AppIntent {
    static let title: LocalizedStringResource = "Capture to Craft"
    static let description = IntentDescription(
        "Opens Craft and starts dictation, then saves what you say to Craft."
    )

    /// Dictation needs the UI, so this intent has to bring the app forward.
    static let openAppWhenRun = true

    @MainActor
    func perform() async throws -> some IntentResult {
        CraftStore.shared.requestCapture()
        return .result()
    }
}

/// Saves text without showing any UI, so a Shortcut can pair "Dictate Text" with this
/// and never bring the app forward — a faster Action button press when you would rather
/// not look at the screen.
struct AddCraftTaskIntent: AppIntent {
    static let title: LocalizedStringResource = "Add Craft Task"
    static let description = IntentDescription(
        "Adds a task to Craft, scheduled for today, without opening the app."
    )

    static let openAppWhenRun = false

    @Parameter(title: "Task", requestValueDialog: "What should the task say?")
    var text: String

    init() {}

    init(text: String) {
        self.text = text
    }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let store = CraftStore.shared
        await store.prepare()

        guard store.isConnected else {
            throw CraftError.notConnected
        }

        await store.capture(text, to: .task)

        // Queued rather than sent is worth saying out loud: the text is safe either way,
        // but the task is not in Craft yet.
        if store.pendingCount > 0 {
            return .result(dialog: "Saved to send when you are back online.")
        }
        return .result(dialog: "Added to Craft.")
    }
}

/// Appends to today's Daily Note instead of creating a task.
struct AddCraftNoteIntent: AppIntent {
    static let title: LocalizedStringResource = "Add Craft Note"
    static let description = IntentDescription(
        "Appends text to today's Daily Note in Craft, without opening the app."
    )

    static let openAppWhenRun = false

    @Parameter(title: "Note", requestValueDialog: "What should the note say?")
    var text: String

    init() {}

    init(text: String) {
        self.text = text
    }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let store = CraftStore.shared
        await store.prepare()

        guard store.isConnected else {
            throw CraftError.notConnected
        }

        await store.capture(text, to: .dailyNote)

        if store.pendingCount > 0 {
            return .result(dialog: "Saved to send when you are back online.")
        }
        return .result(dialog: "Added to your Daily Note.")
    }
}

/// Publishes the capture intent to Shortcuts and Siri so it can be picked in
/// Settings ▸ Action Button ▸ Shortcut.
///
/// Only the zero-parameter intent is listed here; the two text intents take a required
/// parameter and are meant to be composed in the Shortcuts app, where they appear as
/// actions automatically.
struct CraftShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: CaptureToCraftIntent(),
            phrases: [
                "Capture to \(.applicationName)",
                "New \(.applicationName) note",
                "Dictate to \(.applicationName)",
            ],
            shortTitle: "Capture",
            systemImageName: "mic.fill"
        )
    }
}
