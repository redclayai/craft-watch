import SwiftUI

@main
struct CraftWatchPhoneApp: App {
    @State private var model = SetupModel()

    var body: some Scene {
        WindowGroup {
            SetupView()
                .environment(model)
                .task { model.load() }
        }
    }
}
