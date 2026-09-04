import SwiftUI

struct SettingsView: View {
    @Environment(CraftStore.self) private var store
    @State private var confirmDisconnect = false

    var body: some View {
        List {
            Section("Connection") {
                LabeledContent("Space", value: store.spaceName ?? "Craft")
                if let lastRefresh = store.lastRefresh {
                    LabeledContent("Updated", value: lastRefresh.formatted(date: .omitted, time: .shortened))
                }
            }

            Section("Save dictation to") {
                Picker("Destination", selection: Binding(
                    get: { store.destination },
                    set: { store.destination = $0 }
                )) {
                    ForEach(CraftAPI.Destination.allCases) { destination in
                        Label(destination.label, systemImage: destination.symbol)
                            .tag(destination)
                    }
                }
                .pickerStyle(.inline)
            }

            if store.pendingCount > 0 {
                Section("Queue") {
                    Button("Send \(store.pendingCount) now") {
                        Task { await store.flushPending() }
                    }
                }
            }

            Section {
                Button("Disconnect", role: .destructive) { confirmDisconnect = true }
            }
        }
        .navigationTitle("Settings")
        .confirmationDialog(
            "Disconnect from Craft?",
            isPresented: $confirmDisconnect,
            titleVisibility: .visible
        ) {
            Button("Disconnect", role: .destructive) {
                Task { await store.disconnect() }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Queued captures will be discarded. You will need to reconnect from your iPhone.")
        }
    }
}
