import SwiftUI

#if !os(tvOS)
struct TabBarOnlyModifier: ViewModifier {
    func body(content: Content) -> some View {
        if #available(iOS 18.0, *) {
            content.tabViewStyle(.tabBarOnly)
        } else {
            content
        }
    }
}
#endif

struct ContentView: View {
    @EnvironmentObject var api: MuxAPI
    @State private var sermonsUnlocked = false

    var body: some View {
        ZStack(alignment: .top) {
            tabContent

            #if os(tvOS)
            HStack {
                Text("Gospel Outreach")
                    .font(.system(size: 28, weight: .bold))
                    .foregroundColor(.white)
                    .padding(.leading, 20)
                    .offset(y: -12)
                Spacer()
            }
            .frame(height: 64)
            .zIndex(999)
            .allowsHitTesting(false)
            #endif
        }
    }

    @ViewBuilder
    var tabContent: some View {
        TabView {
            NavigationStack { HomeView() }
                .tabItem { Label("Home", systemImage: "house.fill") }

            NavigationStack {
                if sermonsUnlocked {
                    SermonLibraryView()
                } else {
                    PinLockView { sermonsUnlocked = true }
                }
            }
            .tabItem { Label("Sermons", systemImage: "film.stack") }

            NavigationStack {
                CategoryLibraryView(title: "Children's", category: "children", icon: "star.circle.fill")
            }
            .tabItem { Label("Children's", systemImage: "star.circle.fill") }

            NavigationStack {
                CategoryLibraryView(title: "Music", category: "music", icon: "music.note.tv.fill")
            }
            .tabItem { Label("Music", systemImage: "music.note.tv.fill") }

            NavigationStack {
                CategoryLibraryView(title: "Performances", category: "performance", icon: "theatermasks.fill")
            }
            .tabItem { Label("Shows", systemImage: "theatermasks.fill") }

            NavigationStack { PlaylistsView() }
                .tabItem { Label("Lists", systemImage: "music.note.list") }

            #if os(tvOS)
            NavigationStack { SearchView() }
                .tabItem { Label("Search", systemImage: "magnifyingglass") }
                .tag(99)
            #endif
        }
        #if !os(tvOS)
        .modifier(TabBarOnlyModifier())
        #endif
    }
}
