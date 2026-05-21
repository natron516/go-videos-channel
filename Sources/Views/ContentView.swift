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
    case home, sermons, children, music, performance, funzone, listen, playlists, search, privateContent
    var id: Int { rawValue }

    var title: String {
        switch self {
        case .home:            return "Home"
        case .sermons:         return "Sermons"
        case .children:        return "Children"
        case .music:           return "Music"
        case .performance:     return "Shows"
        case .funzone:         return "FunZone"
        case .listen:          return "Listen"
        case .playlists:       return "Playlists"
        case .search:          return "Search"
        case .privateContent:  return "Private"
        }
    }

    var icon: String {
        switch self {
        case .home:            return "house.fill"
        case .sermons:         return "film.stack"
        case .children:        return "star.circle.fill"
        case .music:           return "music.note.tv.fill"
        case .performance:     return "theatermasks.fill"
        case .funzone:         return "party.popper.fill"
        case .listen:          return "headphones"
        case .playlists:       return "music.note.list"
        case .search:          return "magnifyingglass"
        case .privateContent:  return "lock.fill"
        }
    }

    /// The Mux asset category this section displays, or nil if not category-based.
    var assetCategory: String? {
        switch self {
        case .sermons:         return "sermon"
        case .children:        return "children"
        case .music:           return "music"
        case .performance:     return "performance"
        case .funzone:         return "funzone"
        case .privateContent:  return "hidden"
        default:               return nil
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
    case autoplay, shuffle, timer, profile
}

struct TVSidebar: View {
    @Binding var selection: TVSection
    @FocusState private var focused: SidebarFocus?
    @Namespace private var sidebarNS
    @ObservedObject private var autoplay = AutoplayManager.shared
    @ObservedObject private var auth = AuthService.shared
    @ObservedObject private var liveManager = LiveStreamManager.shared
    @EnvironmentObject var api: MuxAPI
    @State private var showDeleteConfirm = false
    @State private var showDeleteError = false
    @State private var showProfileMenu = false
    @State private var showFeedback = false
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
                    .padding(.top, 70)
                    .padding(.bottom, 16)
            }

            // Categories — no extra spacing, tightly packed
            ForEach(TVSection.allCases.filter {
                $0 != .listen && ($0 != .privateContent || auth.hasPrivateAccess)
            }) { section in
                let isLiveSection = section.assetCategory != nil &&
                    (liveManager.liveAsset?.category ?? "") == section.assetCategory
                Button { selection = section } label: {
                    TVSidebarItem(section: section, isSelected: selection == section, isLive: isLiveSection)
                }
                .buttonStyle(TVPlainButtonStyle())
                .focused($focused, equals: .section(section))
                .prefersDefaultFocus(section == selection, in: sidebarNS)
            }

            // Controls — below categories
            Spacer().frame(height: 20)
            Divider()
                .background(Color.white.opacity(0.15))
                .padding(.horizontal, 16)
                .padding(.bottom, 12)

            VStack(spacing: 16) {
                HStack(spacing: 24) {
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
                HStack(spacing: 24) {
                    Button { showProfileMenu = true } label: {
                        TVCircleLabel(icon: "person.circle", color: .white, label: "Profile")
                    }
                    .buttonStyle(TVPlainButtonStyle())
                    .focused($focused, equals: .profile)

                    Button { showWatchTimer = true } label: {
                        TVCircleLabel(icon: "timer",
                                      color: watchTimer.isRunning ? .orange : .white, label: "Timer")
                    }
                    .buttonStyle(TVPlainButtonStyle())
                    .focused($focused, equals: .timer)
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 20)
        }
        .frame(maxHeight: .infinity)
        .background(Color.black.opacity(0.55))
        .focusScope(sidebarNS)
        .focusSection()
        .onChange(of: focused) { newVal in
            guard let newVal = newVal else { return }
            if case .section(let s) = newVal {
                selection = s
            }
        }
        .onChange(of: selection) { newVal in
            if focused != .section(newVal) {
                focused = .section(newVal)
            }
        }
        .onAppear { focused = .section(selection) }
        .fullScreenCover(isPresented: $showWatchTimer) { WatchTimerSetupView() }
        .confirmationDialog("Profile", isPresented: $showProfileMenu) {
            Button("Send Feedback") { showFeedback = true }
            Button("Sign Out") { AuthService.shared.signOut() }
            Button("Delete Account", role: .destructive) { showDeleteConfirm = true }
            Button("Cancel", role: .cancel) { }
        }
        .sheet(isPresented: $showFeedback) { FeedbackView() }
        .alert("Delete Account", isPresented: $showDeleteConfirm) {
            Button("Cancel", role: .cancel) { }
            Button("Delete", role: .destructive) {
                Task {
                    await AuthService.shared.deleteAccount()
                    if AuthService.shared.deleteError != nil {
                        showDeleteError = true
                    }
                }
            }
        } message: {
            Text("Are you sure? This will permanently delete your account and all associated data. This action cannot be undone.")
        }
        .alert("Error", isPresented: $showDeleteError) {
            Button("OK") { AuthService.shared.deleteError = nil }
        } message: {
            Text(AuthService.shared.deleteError ?? "Unknown error")
        }
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
    var isLive: Bool = false
    @Environment(\.isFocused) var isFocused
    @ObservedObject private var liveManager = LiveStreamManager.shared

    private var hasLive: Bool {
        guard liveManager.isLive,
              let cat = section.assetCategory,
              let liveCat = liveManager.liveCategory else { return false }
        return liveCat == cat
    }

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: section.icon)
                .font(.system(size: 26, weight: .medium))
                .frame(width: 32, alignment: .center)
                .foregroundColor(.white)
            Text(section.title)
                .font(.system(size: 28, weight: isSelected ? .semibold : .regular))
                .lineLimit(1)
                .foregroundColor(.white)
            if hasLive {
                Circle()
                    .fill(Color.red)
                    .frame(width: 10, height: 10)
            }
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 15)
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
    @State private var sermonUnlocked = PinUnlockManager.shared.isUnlocked
    @ObservedObject private var liveManager = LiveStreamManager.shared

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
                    .frame(width: 290)

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

        .task {
            // Authoritative live stream poller — only this source clears the live state
            while !Task.isCancelled {
                let stream = try? await api.activeLiveStream()
                let assets = (try? await api.fetchAssets()) ?? []
                await MainActor.run {
                    LiveStreamManager.shared.update(stream: stream, allAssets: assets, authoritative: true)
                }
                try? await Task.sleep(nanoseconds: 30_000_000_000)
            }
        }
        .onAppear {
            PinUnlockManager.shared.validateUnlock { valid in
                DispatchQueue.main.async { sermonUnlocked = valid }
            }
        }
        .onChange(of: selection) { _ in
            navPath = NavigationPath()
            // Re-validate PIN when switching to sermons (catches admin PIN changes)
            if selection == .sermons {
                PinUnlockManager.shared.validateUnlock { valid in
                    DispatchQueue.main.async { sermonUnlocked = valid }
                }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: AppNavigator.navigateToSermonsNotification)) { _ in
            selection = .sermons
        }
    }

    @ViewBuilder
    var detailView: some View {
        switch selection {
        case .home:        HomeView()
        case .sermons:
            ZStack {
                // Always present so it pre-loads while PIN is showing.
                // Disabled keeps focus out of the grid until unlocked.
                SermonLibraryView()
                    .disabled(!sermonUnlocked)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                if !sermonUnlocked {
                    PinLockView {
                        PinUnlockManager.shared.unlock()
                        sermonUnlocked = true
                    }
                        .background(Color.black)
                        .ignoresSafeArea()
                        .focusSection()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .children:    CategoryLibraryView(title: "Children's",   category: "children",    icon: "star.circle.fill")
        case .music:       CategoryLibraryView(title: "Music",        category: "music",       icon: "music.note.tv.fill")
        case .performance: CategoryLibraryView(title: "Shows",        category: "performance", icon: "theatermasks.fill")
        case .funzone:     CategoryLibraryView(title: "FunZone",      category: "funzone",     icon: "party.popper.fill")
        case .listen:          AppleMusicView()
        case .playlists:       PlaylistsView()
        case .search:          SearchView()
        case .privateContent:  CategoryLibraryView(title: "Private", category: "hidden", icon: "lock.fill", includePrivate: true)
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
        .onReceive(NotificationCenter.default.publisher(for: AppNavigator.navigateToSermonsNotification)) { _ in
            selectedTab = 1
        }
        #endif
    }

    #if !os(tvOS)
    @State private var selectedTab: Int = 0
    @ObservedObject private var auth = AuthService.shared
    @ObservedObject private var liveManager = LiveStreamManager.shared

    /// Returns true when a live stream is active in the given Mux category.
    private func isLive(_ category: String) -> Bool {
        guard liveManager.isLive, let liveCat = liveManager.liveCategory else { return false }
        return liveCat == category
    }



    @ViewBuilder
    var mainTabs: some View {
        TabView(selection: $selectedTab) {
            NavigationStack { HomeView() }
                .tabItem { Label("Home", systemImage: "house.fill") }
                .tag(0)

            NavigationStack { SermonLibraryView() }
                .tabItem { Label(isLive("sermon") ? "🔴 Sermons" : "Sermons", systemImage: "film.stack") }
                .tag(1)

            NavigationStack {
                CategoryLibraryView(title: "Children's", category: "children", icon: "star.circle.fill")
            }
            .tabItem { Label(isLive("children") ? "🔴 Children's" : "Children's", systemImage: "star.circle.fill") }
            .tag(2)

            NavigationStack {
                CategoryLibraryView(title: "Music", category: "music", icon: "music.note.tv.fill")
            }
            .tabItem { Label(isLive("music") ? "🔴 Music" : "Music", systemImage: "music.note.tv.fill") }
            .tag(3)

            NavigationStack {
                CategoryLibraryView(title: "Performances", category: "performance", icon: "theatermasks.fill")
            }
            .tabItem { Label(isLive("performance") ? "🔴 Shows" : "Shows", systemImage: "theatermasks.fill") }
            .tag(4)

            NavigationStack {
                CategoryLibraryView(title: "FunZone", category: "funzone", icon: "party.popper.fill")
            }
            .tabItem { Label(isLive("funzone") ? "🔴 FunZone" : "FunZone", systemImage: "party.popper.fill") }
            .tag(5)

            NavigationStack { PlaylistsView() }
                .tabItem { Label("Lists", systemImage: "music.note.list") }
                .tag(6)

            if auth.hasPrivateAccess {
                NavigationStack {
                    CategoryLibraryView(title: "Private", category: "hidden", icon: "lock.fill", includePrivate: true)
                }
                .tabItem { Label(isLive("hidden") ? "🔴 Private" : "Private", systemImage: "lock.fill") }
                .tag(7)
            }
        }

        .task {
            // Authoritative live stream poller for iOS (mirrors tvOS poller)
            while !Task.isCancelled {
                let stream = try? await api.activeLiveStream()
                let assets = (try? await api.fetchAllAssets()) ?? []
                await MainActor.run {
                    LiveStreamManager.shared.update(stream: stream, allAssets: assets, authoritative: true)
                }
                try? await Task.sleep(nanoseconds: 30_000_000_000)
            }
        }
    }
    #endif
}
