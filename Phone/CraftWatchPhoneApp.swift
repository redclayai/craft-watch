import SwiftUI

@main
struct CraftWatchPhoneApp: App {
    @State private var model = SetupModel()

    var body: some Scene {
        WindowGroup {
            SetupView()
                .environment(model)
                .task {
#if DEBUG
                    if ProcessInfo.processInfo.environment["CRAFT_DEMO"] == "1" {
                        model.seedDemo()
                        return
                    }
#endif
                    model.load()
                }
        }
    }
}
