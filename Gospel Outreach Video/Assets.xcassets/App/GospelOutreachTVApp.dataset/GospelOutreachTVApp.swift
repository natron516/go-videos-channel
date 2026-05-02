import SwiftUI

@main
struct GospelOutreachTVApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(MuxAPI.shared)
        }
    }
}
