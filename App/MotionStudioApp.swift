import SwiftUI

@main
struct MotionStudioApp: App {
    @State private var store = ProjectStore()
    @AppStorage(AppearanceSetting.storageKey) private var appearanceName = AppearanceSetting.system.rawValue
    @AppStorage("motionStudioAccentHex") private var accentHex = "#648CFF"

    private var appearance: AppearanceSetting {
        AppearanceSetting(rawValue: appearanceName) ?? .system
    }

    var body: some Scene {
        WindowGroup {
            RootView(store: store)
                .preferredColorScheme(appearance.colorScheme)
                .tint(Color(hex: accentHex))
        }
    }
}
