import SwiftUI
import FirebaseCore

@main
struct GospelOutreachTVApp: App {
    init() {
        FirebaseApp.configure()
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(MuxAPI.shared)
                .preferredColorScheme(.dark)
        }
    }
}
