import SwiftUI

struct SetupView: View {
    @Environment(SetupModel.self) private var model

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

                case let .connected(space, sentToWatch):
                    Section("Connected") {
                        LabeledContent("Space", value: space ?? "Craft")
                        LabeledContent("Watch") {
                            Label(
                                sentToWatch ? "Credentials sent" : "Not sent yet",
                                systemImage: sentToWatch ? "checkmark.circle.fill" : "exclamationmark.circle"
                            )
                            .foregroundStyle(sentToWatch ? .green : .orange)
                        }
                        Button("Send to Watch again") { model.resend() }
                    }
                    Section {
                        Text("Open Craft Watch on your Apple Watch to finish. If it still says “Connect Craft” after a minute, tap Send to Watch again.")
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

                if !model.isWatchPaired {
                    Section {
                        Label("No Apple Watch with Craft Watch installed was found yet.", systemImage: "applewatch.slash")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle("Craft Watch")
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
}
