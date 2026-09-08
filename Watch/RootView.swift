import SwiftUI

struct RootView: View {
    @Environment(CraftStore.self) private var store
    @State private var showCapture = false

    var body: some View {
        NavigationStack {
            Group {
                if store.isConnected {
                    connectedList
                } else {
                    ConnectPromptView()
                }
            }
            .navigationTitle("Craft")
            .toolbar {
                if store.isConnected {
                    ToolbarItem(placement: .topBarTrailing) {
                        NavigationLink {
                            SettingsView()
                        } label: {
                            Image(systemName: "gearshape")
                        }
                    }
                }
            }
        }
        .sheet(isPresented: $showCapture) {
            CaptureSheet { text in
                Task { await store.capture(text) }
            }
        }
        .onOpenURL { url in
            // Tapping the complication should land straight in dictation.
            if url.host == "capture" || url.path == "/capture" { store.requestCapture() }
        }
        // The Action button runs CaptureToCraftIntent, which only sets this — presenting
        // the sheet is the view's job.
        .onChange(of: store.captureRequestID) { _, id in
            if id != nil { showCapture = true }
        }
        .onChange(of: showCapture) { _, isShowing in
            if !isShowing { store.clearCaptureRequest() }
        }
    }

    private var connectedList: some View {
        List {
            Section {
                TextFieldLink(prompt: Text(store.destination.label)) {
                    Label("Speak", systemImage: "mic.fill")
                        .frame(maxWidth: .infinity)
                } onSubmit: { text in
                    Task { await store.capture(text) }
                }
                .buttonStyle(.borderedProminent)

                DestinationToggle()
            }

            if case let .saved(message) = store.status {
                StatusBanner(message: message, tone: .success)
            } else if case let .failed(message) = store.status {
                StatusBanner(message: message, tone: .failure)
            }

            if store.pendingCount > 0 {
                Section {
                    Button {
                        Task { await store.flushPending() }
                    } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Label(
                                "\(store.pendingCount) waiting to send",
                                systemImage: "arrow.up.circle"
                            )
                            // Without this a stuck queue is indistinguishable from a
                            // queue that is merely offline.
                            if let reason = store.lastCaptureError {
                                Text(reason)
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(3)
                            }
                        }
                    }
                }
            }

            Section("Today") {
                if store.tasks.isEmpty {
                    Text(store.status == .working ? "Loading…" : "Nothing due. Nice.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(store.tasks) { task in
                        TaskRow(task: task) {
                            Task { await store.complete(task) }
                        }
                    }
                }
            }
        }
        .refreshable { await store.refresh() }
    }
}

private struct DestinationToggle: View {
    @Environment(CraftStore.self) private var store

    var body: some View {
        Button {
            store.destination = store.destination == .task ? .dailyNote : .task
        } label: {
            HStack {
                Label(store.destination.label, systemImage: store.destination.symbol)
                Spacer()
                Image(systemName: "arrow.triangle.2.circlepath")
                    .foregroundStyle(.secondary)
                    .font(.footnote)
            }
        }
        .accessibilityHint("Switches where dictated text is saved")
    }
}

private struct StatusBanner: View {
    enum Tone { case success, failure }

    let message: String
    let tone: Tone

    var body: some View {
        Label(message, systemImage: tone == .success ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
            .font(.footnote)
            .foregroundStyle(tone == .success ? Color.green : Color.orange)
    }
}

struct TaskRow: View {
    let task: CraftTask
    let onComplete: () -> Void

    var body: some View {
        Button(action: onComplete) {
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: "circle")
                    .foregroundStyle(task.isOverdue ? Color.orange : Color.accentColor)
                VStack(alignment: .leading, spacing: 2) {
                    Text(task.text)
                        .lineLimit(3)
                    if let subtitle {
                        Text(subtitle)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(task.text)
        .accessibilityHint("Marks the task complete in Craft")
    }

    private var subtitle: String? {
        var parts: [String] = []
        if task.isOverdue, let date = task.taskDate {
            parts.append("Overdue " + date.formatted(.dateTime.month(.abbreviated).day()))
        }
        if let container = task.container, container != "inbox" {
            parts.append(container)
        }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }
}
