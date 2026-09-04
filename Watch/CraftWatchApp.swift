import SwiftUI

@main
struct CraftWatchApp: App {
    @State private var store = CraftStore.shared
    private let connectivity = WatchConnectivityReceiver.shared

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(store)
                .task {
#if DEBUG
                    if ProcessInfo.processInfo.environment["CRAFT_DEMO"] == "1" {
                        store.seedDemo()
                        return
                    }
#endif
                    connectivity.activate()
                    await store.bootstrap()
                }
        }
    }
}
