import SwiftUI

struct SetupView: View {
    @Environment(SetupModel.self) private var model

    /// Read directly so the view updates when WCSession finishes activating, which
    /// happens after `SetupModel.load()` has already returned.
    @State private var connectivity = PhoneConnectivity.shared

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Craft on your wrist")
                            .font(.headline)
                        Text("Sign in once here. The Watch app then talks to Craft directly, so dictating a task works even when this iPhone is locked or nowhere nearby.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 4)
                }

                StateSections(handoff: handoff)
            }
            .navigationTitle("Craft Watch")
        }
    }

    private var handoff: HandoffStatus {
        HandoffStatus.current(for: connectivity)
    }
}

// MARK: - State sections

private struct StateSections: View {
    @Environment(SetupModel.self) private var model
    let handoff: HandoffStatus

    var body: some View {
        switch model.state {
        case .idle:
            Group {
                connectSection(title: "Connect Craft")
                missingWatchHint
            }

        case .connecting:
            Section {
                HStack(spacing: 10) {
                    ProgressView()
                    Text("Waiting for Craft…")
                }
            }

        case let .connected(space):
            Group {
                Section("Connected") {
                    LabeledContent("Space", value: space ?? "Craft")
                    // A plain HStack rather than LabeledContent with custom content:
                    // the latter stretches its row to fill the section inside a Form.
                    HStack(spacing: 6) {
                        Text("Watch")
                        Spacer(minLength: 12)
                        Image(systemName: handoff.symbol)
                            .foregroundStyle(handoff.tint)
                        Text(handoff.label)
                            .multilineTextAlignment(.trailing)
                            .foregroundStyle(handoff.tint)
                    }
                    Button("Send to Watch again") { model.resend() }
                }
                Section {
                    Text(handoff.detail)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                Section {
                    Button("Disconnect", role: .destructive) { model.reset() }
                }
            }

        case let .failed(message):
            Group {
                Section {
                    Label(message, systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                        .font(.footnote)
                }
                connectSection(title: "Try again")
                missingWatchHint
            }
        }
    }

    private func connectSection(title: String) -> some View {
        Section {
            Button {
                Task { await model.connect() }
            } label: {
                Label(title, systemImage: "link")
            }
        }
    }

    @ViewBuilder
    private var missingWatchHint: some View {
        if handoff.isWatchMissing {
            Section {
                Label(
                    "No Apple Watch with Craft Watch installed was found. You can still sign in — the credentials are held and sent as soon as the Watch app appears.",
                    systemImage: "applewatch.slash"
                )
                .font(.footnote)
                .foregroundStyle(.secondary)
            }
        }
    }
}

// MARK: - Handoff status

struct HandoffStatus {
    let label: String
    let symbol: String
    let tint: Color
    let detail: String
    var isWatchMissing = false

    static func current(for connectivity: PhoneConnectivity) -> HandoffStatus {
        if !connectivity.isSupported {
            return HandoffStatus(
                label: "Not available",
                symbol: "applewatch.slash",
                tint: .secondary,
                detail: "This device cannot pair with an Apple Watch, so there is nothing to hand off to."
            )
        }
        if !connectivity.isActivated {
            return HandoffStatus(
                label: "Connecting…",
                symbol: "ellipsis.circle",
                tint: .secondary,
                detail: "Starting the Watch connection."
            )
        }
        if !connectivity.isWatchAppAvailable {
            return HandoffStatus(
                label: "Watch app not installed",
                symbol: "applewatch.slash",
                tint: .orange,
                detail: "Install Craft Watch on your Apple Watch. Your credentials are saved and will be sent as soon as it appears.",
                isWatchMissing: true
            )
        }
        if connectivity.hasDeliveredCredentials {
            return HandoffStatus(
                label: "Confirmed by Watch",
                symbol: "checkmark.circle.fill",
                tint: .green,
                detail: "The Watch has the connection and works on its own from here."
            )
        }
        if connectivity.isAwaitingWatch {
            return HandoffStatus(
                label: "Waiting for Watch",
                symbol: "clock",
                tint: .orange,
                detail: "Sent, but the Watch has not confirmed yet. Open Craft on your Apple Watch."
            )
        }
        return HandoffStatus(
            label: "Not sent yet",
            symbol: "exclamationmark.circle",
            tint: .orange,
            detail: "Tap Send to Watch again."
        )
    }
}
