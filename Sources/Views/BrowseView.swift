import SwiftUI

/// BrowseView is kept for backward compatibility but is no longer used as a main tab.
/// The new tab structure (Discover, Watch, Listen, Read, Library) replaces this.
#if !os(tvOS)
struct BrowseView: View {
    @ObservedObject private var auth = AuthService.shared
    @State private var showLinkTV = false
    @State private var showWatchTimer = false
    @State private var showSearch = false

    var body: some View {
        List {
            Section("Video Categories") {
                NavigationLink {
                    CategoryLibraryView(title: "Shows", category: "performance", icon: "theatermasks.fill")
                } label: {
                    Label("Shows", systemImage: "theatermasks.fill")
                }

                NavigationLink {
                    CategoryLibraryView(title: "FunZone", category: "funzone", icon: "party.popper.fill")
                } label: {
                    Label("FunZone", systemImage: "party.popper.fill")
                }
            }

            Section("Library") {
                NavigationLink {
                    PlaylistsView()
                } label: {
                    Label("Library", systemImage: "books.vertical.fill")
                }

                NavigationLink {
                    DownloadsView()
                } label: {
                    Label("Downloads", systemImage: "arrow.down.circle.fill")
                }
            }

            if auth.hasPrivateAccess {
                Section {
                    NavigationLink {
                        CategoryLibraryView(title: "Private", category: "hidden", icon: "lock.fill", includePrivate: true)
                    } label: {
                        Label("Private", systemImage: "lock.fill")
                    }
                }
            }
        }
        .navigationTitle("Browse")
        .goNavBar(showLinkTV: $showLinkTV, showWatchTimer: $showWatchTimer, showSearch: $showSearch)
        .sheet(isPresented: $showLinkTV) { LinkTVView() }
        .sheet(isPresented: $showSearch) { NavigationStack { SearchView() } }
        .sheet(isPresented: $showWatchTimer) { WatchTimerSetupView() }
        .appBackground()
    }
}
#endif
