import SwiftUI

/// iOS-only: Sermons, Performances, Search
struct BrowseView: View {
    @State private var sermonsUnlocked = false
    @State private var showSearch = false

    var body: some View {
        List {
            NavigationLink {
                if sermonsUnlocked {
                    SermonLibraryView()
                } else {
                    PinLockView { sermonsUnlocked = true }
                }
            } label: {
                Label("Sermons", systemImage: "film.stack")
            }
            NavigationLink {
                CategoryLibraryView(title: "Performances", category: "performance", icon: "theatermasks.fill")
            } label: {
                Label("Performances", systemImage: "theatermasks.fill")
            }
            NavigationLink {
                SearchView()
            } label: {
                Label("Search", systemImage: "magnifyingglass")
            }
        }
        .navigationTitle("More")
    }
}
