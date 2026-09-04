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

                switch model.state {
                case .idle:
                    connectSection(title: "Connect Craft")

                case .connecting:
                    Section {
                        HStack(spacing: 10) {
                            ProgressView()
                            Text("Waiting for Craft…")
                        }
                    }

                case let .connected(space):
                    Section("Connected") {
                        LabeledContent("Space", value: space ?? "Craft")
                        LabeledContent("Watch") {
                            Label(handoff.label, systemImage: handoff.symbol)
                                .foregroundStyle(handoff.tint)
                        }
                        Button("Send to Watch again") { model.resend() }
                            .disabled(!connectivity.isActivated)
                    }
                    Section {
                        Text(handoff.detail)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                    Section {
                        Button("Disconnect", role: .destructive) { model.reset() }
                    }

                case let .failed(message):
                    Section {
                        Label(message, systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                            .font(.footnote)
                    }
                    connectSection(title: "Try again")
                }

                if showsMissingWatchHint {
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
            .navigationTitle("Craft Watch")
        }
    }

    /// Only worth saying once activation has actually answered, and only before the
    /// connected state starts reporting handoff status itself.
    private var showsMissingWatchHint: Bool {
        guard connectivity.isSupported, connectivity.isActivated, !connectivity.isWatchAppAvailable else {
            return false
        }
        switch model.state {
        case .idle, .failed: return true
        case .connecting, .connected: return false
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

    // MARK: - Handoff status

    private struct Handoff {
        let label: String
        let symbol: String
        let tint: Color
        let detail: String
    }

    private var handoff: Handoff {
        if !connectivity.isSupported {
            return Handoff(
                label: "Not available",
                symbol: "applewatch.slash",
                tint: .secondary,
                detail: "This device cannot pair with an Apple Watch, so there is nothing to hand off to."
            )
        }
        if !connectivity.isActivated {
            return Handoff(
                label: "Connecting…",
                symbol: "ellipsis.circle",
                tint: .secondary,
                detail: "Starting the Watch connection."
            )
        }
        if !connectivity.isWatchAppAvailable {
            return Handoff(
                label: "Watch app not installed",
                symbol: "applewatch.slash",
                tint: .orange,
                detail: "Install Craft Watch on your Apple Watch. Your credentials are saved and will be sent as soon as it appears."
            )
        }
        if connectivity.hasDeliveredCredentials {
            return Handoff(
                label: "Credentials sent",
                symbol: "checkmark.circle.fill",
                tint: .green,
                detail: "Open Craft on your Apple Watch to finish. If it still says “Connect Craft” after a minute, tap Send to Watch again."
            )
        }
        return Handoff(
            label: "Not sent yet",
            symbol: "exclamationmark.circle",
            tint: .orange,
            detail: "Tap Send to Watch again."
        )
    }
}
