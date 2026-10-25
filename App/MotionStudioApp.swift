import SwiftUI

@main
struct MotionStudioApp: App {
    @State private var store = ProjectStore()

    var body: some Scene {
        WindowGroup {
            RootView(store: store)
                .preferredColorScheme(.dark)
                .tint(Theme.accent)
        }
    }
}
