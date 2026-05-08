import SwiftUI

// ── iOS-only tab bar modifier ─────────────────────────────
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

// ─────────────────────────────────────────────────────────
// MARK: - tvOS persistent split layout
// ─────────────────────────────────────────────────────────
#if os(tvOS)

enum TVSection: Int, CaseIterable, Identifiable {
    case home, sermons, children, music, performance, funzone, listen, playlists, search
    var id: Int { rawValue }

    var title: String {
        switch self {
        case .home:        return "Home"
        case .sermons:     return "Sermons"
        case .children:    return "Children's"
        case .music:       return "Music"
        case .performance: return "Shows"
        case .funzone:     return "FunZone"
        case .listen:      return "Listen"
        case .playlists:   return "Playlists"
        case .search:      return "Search"
        }
    }

    var icon: String {
        switch self {
        case .home:        return "house.fill"
        case .sermons:     return "film.stack"
        case .children:    return "star.circle.fill"
        case .music:       return "music.note.tv.fill"
        case .performance: return "theatermasks.fill"
        case .funzone:     return "party.popper.fill"
        case .listen:      return "headphones"
        case .playlists:   return "music.note.list"
        case .search:      return "magnifyingglass"
        }
    }
}

// ── Sidebar ───────────────────────────────────────────────
// Suppresses ALL default tvOS button scaling/focus effects
private struct TVPlainButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
    }
}

private enum SidebarFocus: Hashable {
    case section(TVSection)
    case autoplay, shuffle, timer, signOut
}

struct TVSidebar: View {
    @Binding var selection: TVSection
    @FocusState private var focused: SidebarFocus?
    @ObservedObject private var autoplay = AutoplayManager.shared
    @ObservedObject private var watchTimer = WatchTimerManager.shared
    @State private var showWatchTimer = false

    var body: some View {
        // No ScrollView — everything sized to fit the screen so all items are always focusable
        VStack(alignment: .leading, spacing: 0) {
            // Logo
            if let uiImage = UIImage(named: "NavLogo") {
                Image(uiImage: uiImage)
                    .resizable()
                    .interpolation(.high)
                    .scaledToFit()
                    .frame(height: 130)
                    .padding(.horizontal, 16)
                    .padding(.top, 50)
                    .padding(.bottom, 12)
            }

            // Categories — no extra spacing, tightly packed
            ForEach(TVSection.allCases.filter { $0 != .listen }) { section in
                Button { selection = section } label: {
                    TVSidebarItem(section: section, isSelected: selection == section)
                }
                .buttonStyle(TVPlainButtonStyle())
                .focused($focused, equals: .section(section))
            }

            // Controls — below categories
            Spacer().frame(height: 20)
            Divider()
                .background(Color.white.opacity(0.15))
                .padding(.horizontal, 16)
                .padding(.bottom, 12)

            VStack(spacing: 12) {
                HStack(spacing: 20) {
                    Button { autoplay.enabled.toggle() } label: {
                        TVCircleLabel(icon: autoplay.enabled ? "forward.end.fill" : "forward.end",
                                      color: autoplay.enabled ? .blue : .white, label: "AutoPlay")
                    }
                    .buttonStyle(TVPlainButtonStyle())
                    .focused($focused, equals: .autoplay)

                    Button { autoplay.shuffle.toggle() } label: {
                        TVCircleLabel(icon: "shuffle",
                                      color: autoplay.shuffle ? .green : .white, label: "Shuffle")
                    }
                    .buttonStyle(TVPlainButtonStyle())
                    .focused($focused, equals: .shuffle)
                }
                HStack(spacing: 20) {
                    Button { AuthService.shared.signOut() } label: {
                        TVCircleLabel(icon: "person.circle", color: .white, label: "Sign Out")
                    }
                    .buttonStyle(TVPlainButtonStyle())
                    .focused($focused, equals: .signOut)

                    Button { showWatchTimer = true } label: {
                        TVCircleLabel(icon: "timer",
                                      color: watchTimer.isRunning ? .orange : .white, label: "Timer")
                    }
                    .buttonStyle(TVPlainButtonStyle())
                    .focused($focused, equals: .timer)
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 10)
        }
        .frame(maxHeight: .infinity)
        .background(Color.black.opacity(0.55))
        .focusSection()
        .onChange(of: focused) { newVal in
            if case .section(let s) = newVal { selection = s }
        }
        .fullScreenCover(isPresented: $showWatchTimer) { WatchTimerSetupView() }
    }
}

struct TVCircleLabel: View {
    let icon: String
    let color: Color
    let label: String
    @Environment(\.isFocused) var isFocused

    var body: some View {
        VStack(spacing: 8) {
            ZStack {
                Circle()
                    .fill(Color.white.opacity(0.12))
                    .frame(width: 76, height: 76)
                    .overlay(
                        Circle()
                            .stroke(Color.white, lineWidth: isFocused ? 3 : 0)
                    )
                Image(systemName: icon)
                    .font(.system(size: 30, weight: .medium))
                    .foregroundColor(color)
            }
            Text(label)
                .font(.system(size: 18, weight: .medium))
                .foregroundColor(.white.opacity(0.85))
        }
        .scaleEffect(isFocused ? 1.06 : 1.0)
        .animation(.easeInOut(duration: 0.12), value: isFocused)
    }
}

struct TVSidebarItem: View {
    let section: TVSection
    let isSelected: Bool
    @Environment(\.isFocused) var isFocused

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: section.icon)
                .font(.system(size: 26, weight: .medium))
                .frame(width: 32, alignment: .center)
                .foregroundColor(.white)
            Text(section.title)
                .font(.system(size: 28, weight: isSelected ? .semibold : .regular))
                .foregroundColor(.white)
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 19)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(
                    isSelected ? Color.white.opacity(0.2) :
                    isFocused  ? Color.white.opacity(0.12) : Color.clear
                )
        )
        .padding(.horizontal, 10)
    }
}

// ── Main tvOS layout ──────────────────────────────────────
struct TVContentView: View {
    @EnvironmentObject var api: MuxAPI
    @State private var selection: TVSection = .home
    @State private var navPath = NavigationPath()

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            Image("AppBackground")
                .resizable()
                .aspectRatio(contentMode: .fill)
                .ignoresSafeArea()
                .opacity(0.35)

            HStack(spacing: 0) {
                TVSidebar(selection: $selection)
                    .frame(width: 320)

                Rectangle()
                    .fill(Color.white.opacity(0.08))
                    .frame(width: 1)

                NavigationStack(path: $navPath) {
                    detailView
                        .id(selection)
                }
                .focusSection()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .onChange(of: selection) { _ in
            navPath = NavigationPath()
        }
    }

    @ViewBuilder
    var detailView: some View {
        switch selection {
        case .home:        HomeView()
        case .sermons:     SermonLibraryView()
        case .children:    CategoryLibraryView(title: "Children's",   category: "children",    icon: "star.circle.fill")
        case .music:       CategoryLibraryView(title: "Music",        category: "music",       icon: "music.note.tv.fill")
        case .performance: CategoryLibraryView(title: "Shows",        category: "performance", icon: "theatermasks.fill")
        case .funzone:     CategoryLibraryView(title: "FunZone",      category: "funzone",     icon: "party.popper.fill")
        case .listen:      AppleMusicView()
        case .playlists:   PlaylistsView()
        case .search:      SearchView()
        }
    }
}
#endif

// ─────────────────────────────────────────────────────────
// MARK: - ContentView
// ─────────────────────────────────────────────────────────
struct ContentView: View {
    @EnvironmentObject var api: MuxAPI

    var body: some View {
        #if os(tvOS)
        TVContentView()
        #else
        ZStack(alignment: .top) {
            mainTabs.modifier(TabBarOnlyModifier())
        }
        #endif
    }

    #if !os(tvOS)
    @ViewBuilder
    var mainTabs: some View {
        TabView {
            NavigationStack { HomeView() }
                .tabItem { Label("Home", systemImage: "house.fill") }

            NavigationStack { SermonLibraryView() }
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

            NavigationStack {
                CategoryLibraryView(title: "FunZone", category: "funzone", icon: "party.popper.fill")
            }
            .tabItem { Label("FunZone", systemImage: "party.popper.fill") }

            NavigationStack { AppleMusicView() }
                .tabItem { Label("Listen", systemImage: "headphones") }

            NavigationStack { PlaylistsView() }
                .tabItem { Label("Lists", systemImage: "music.note.list") }
        }
    }
    #endif
}
