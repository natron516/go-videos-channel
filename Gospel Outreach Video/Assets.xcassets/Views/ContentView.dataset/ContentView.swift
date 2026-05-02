import SwiftUI

struct ContentView: View {
    @EnvironmentObject var api: MuxAPI
    @State private var activeLive: MuxLiveStream?
    @State private var liveChecked = false

    var body: some View {
        TabView {
            // Live tab - shows badge if currently live
            NavigationStack {
                LiveStreamView()
            }
            .tabItem {
                Label("Live", systemImage: activeLive != nil ? "dot.radiowaves.left.and.right" : "video")
            }

            // Sermon library
            NavigationStack {
                SermonLibraryView()
            }
            .tabItem {
                Label("Sermons", systemImage: "film.stack")
            }

            // About / Info
            NavigationStack {
                AboutView()
            }
            .tabItem {
                Label("About", systemImage: "info.circle")
            }
        }
        .task {
            // Check live status for tab badge
            activeLive = try? await api.activeLiveStream()
            liveChecked = true
        }
    }
}
