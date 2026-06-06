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

// ─────────────────────────────────────────────────────────
// MARK: - iOS section enum (shared by iPad sidebar + Browse)
// ─────────────────────────────────────────────────────────
enum iOSSection: Int, CaseIterable, Identifiable {
    case discover, watch, listen, read, library
    var id: Int { rawValue }

    var title: String {
        switch self {
        case .discover: return "Discover"
        case .watch:    return "Watch"
        case .listen:   return "Listen"
        case .read:     return "Read"
        case .library:  return "My Playlists"
        }
    }

    var icon: String {
        switch self {
        case .discover: return "sparkle"
        case .watch:    return "play.rectangle.fill"
        case .listen:   return "headphones"
        case .read:     return "book.fill"
        case .library:  return "bookmark.fill"
        }
    }

    /// For live/new-content badge tracking — watch tab covers all video categories
    var assetCategory: String? { nil }

    static var browseItems: [iOSSection] { [] }
}

// iPad uses a custom bottom tab bar to match iPhone — iPadOS 18+ forces top placement with
// default TabView, so we build our own.
struct iPadContentView: View {
    @EnvironmentObject var api: MuxAPI
    @State private var selectedTab: Int = 0
    @ObservedObject private var liveManager = LiveStreamManager.shared

    private var watchTabTitle: String {
        liveManager.isLive ? "🔴 Watch" : "Watch"
    }

    private struct TabItem: Identifiable {
        let id: Int
        let title: String
        let icon: String
    }

    private var tabs: [TabItem] {
        [
            TabItem(id: 0, title: "Discover", icon: "sparkles"),
            TabItem(id: 1, title: watchTabTitle, icon: "play.rectangle.fill"),
            TabItem(id: 2, title: "Listen", icon: "headphones"),
            TabItem(id: 3, title: "Read", icon: "book.fill"),
            TabItem(id: 4, title: "My Playlists", icon: "bookmark.fill"),
        ]
    }

    var body: some View {
        VStack(spacing: 0) {
            // Content area
            Group {
                switch selectedTab {
                case 0: NavigationStack { HomeView() }
                case 1: NavigationStack { WatchView() }
                case 2: NavigationStack { ListenView() }
                case 3: NavigationStack { ReadView() }
                case 4: NavigationStack { PlaylistsView() }
                default: NavigationStack { HomeView() }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            // Custom bottom tab bar
            HStack {
                ForEach(tabs) { tab in
                    Button {
                        withAnimation(.easeInOut(duration: 0.15)) {
                            selectedTab = tab.id
                        }
                    } label: {
                        VStack(spacing: 4) {
                            Image(systemName: tab.icon)
                                .font(.system(size: 22))
                            Text(tab.title)
                                .font(.caption2)
                        }
                        .foregroundColor(selectedTab == tab.id ? .blue : .secondary)
                        .frame(maxWidth: .infinity)
                    }
                }
            }
            .padding(.top, 10)
            .padding(.bottom, 16)
            .background(
                Rectangle()
                    .fill(.ultraThinMaterial)
                    .overlay(alignment: .top) {
                        Divider()
                    }
            )
        }
        .ignoresSafeArea(.container, edges: .bottom)
        .task {
            while !Task.isCancelled {
                let stream = try? await api.activeLiveStream()
                let assets = (try? await api.fetchAllAssets()) ?? []
                await MainActor.run {
                    LiveStreamManager.shared.update(stream: stream, allAssets: assets, authoritative: true)
                    NewContentTracker.shared.update(assets: assets)
                }
                try? await Task.sleep(nanoseconds: 30_000_000_000)
            }
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
        case .playlists:       return "My Playlists"
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
        case .playlists:       return "bookmark.fill"
        case .search:          return "magnifyingglass"
        case .privateContent:  return "lock.fill"
        }
    }

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

            // Categories
            ForEach(TVSection.allCases.filter {
                $0 != .music && ($0 != .privateContent || auth.hasPrivateAccess)
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
    @ObservedObject private var newContent = NewContentTracker.shared

    private var hasLive: Bool {
        guard liveManager.isLive,
              let cat = section.assetCategory,
              let liveCat = liveManager.liveCategory else { return false }
        return liveCat == cat
    }

    private var hasNew: Bool {
        guard !hasLive, let cat = section.assetCategory else { return false }
        return newContent.hasNew(cat)
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
                .overlay(alignment: .topTrailing) {
                    if hasLive {
                        Circle()
                            .fill(Color.red)
                            .frame(width: 10, height: 10)
                            .offset(x: 14, y: -2)
                    } else if hasNew {
                        Circle()
                            .fill(Color.blue)
                            .frame(width: 10, height: 10)
                            .offset(x: 14, y: -2)
                    }
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

// ── tvOS Listen (Podcasts + Audio) ────────────────────────
enum TVListenSegment: String, CaseIterable {
    case podcasts = "Podcasts"
    case audio = "Audio"
}

struct TVListenView: View {
    @State private var segment: TVListenSegment = .podcasts

    var body: some View {
        VStack(spacing: 0) {
            // Segment picker
            Picker("Listen", selection: $segment) {
                ForEach(TVListenSegment.allCases, id: \.self) { seg in
                    Text(seg.rawValue).tag(seg)
                }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 40)
            .padding(.top, 24)
            .padding(.bottom, 16)

            // Content
            switch segment {
            case .podcasts:
                PodcastListView()
            case .audio:
                AudioListView()
            }
        }
    }
}

// ── Main tvOS layout ──────────────────────────────────────
struct TVContentView: View {
    @EnvironmentObject var api: MuxAPI
    @State private var selection: TVSection = .home
    @State private var navPath = NavigationPath()
    @State private var sermonUnlocked = PinUnlockManager.shared.isUnlocked
    @ObservedObject private var liveManager = LiveStreamManager.shared
    @ObservedObject private var audioPlayer = AudioPlayerManager.shared

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

                ZStack {
                    NavigationStack(path: $navPath) {
                        detailView
                            .id(selection)
                    }
                    .focusSection()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .opacity(audioPlayer.hasItem ? 0 : 1)

                    if audioPlayer.hasItem {
                        TVAudioPlayerView()
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .transition(.opacity)
                    }
                }
            }
        }
        .task {
            while !Task.isCancelled {
                let stream = try? await api.activeLiveStream()
                let assets = (try? await api.fetchAssets()) ?? []
                await MainActor.run {
                    LiveStreamManager.shared.update(stream: stream, allAssets: assets, authoritative: true)
                    NewContentTracker.shared.update(assets: assets)
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
        case .listen:      TVListenView()
        case .playlists:   PlaylistsView()
        case .search:      SearchView()
        case .privateContent: CategoryLibraryView(title: "Private", category: "hidden", icon: "lock.fill", includePrivate: true)
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
        Group {
            if UIDevice.current.userInterfaceIdiom == .pad {
                iPadContentView()
            } else {
                ZStack(alignment: .top) {
                    mainTabs.modifier(TabBarOnlyModifier())
                }
                .onReceive(NotificationCenter.default.publisher(for: AppNavigator.navigateToSermonsNotification)) { _ in
                    selectedTab = 1 // Watch tab
                }
            }
        }
        #endif
    }

    #if !os(tvOS)
    @State private var selectedTab: Int = {
        if let arg = ProcessInfo.processInfo.arguments.first(where: { $0.hasPrefix("--tab=") }) {
            return Int(arg.replacingOccurrences(of: "--tab=", with: "")) ?? 0
        }
        return 0
    }()
    @ObservedObject private var liveManager = LiveStreamManager.shared

    private var watchTabTitle: String {
        liveManager.isLive ? "🔴 Watch" : "Watch"
    }

    @ViewBuilder
    var mainTabs: some View {
        TabView(selection: $selectedTab) {
            // 0 — Discover
            NavigationStack { HomeView() }
                .navigationTitle("")
                .tabItem { Label("Discover", systemImage: "sparkle") }
                .tag(0)

            // 1 — Watch
            NavigationStack { WatchView() }
                .tabItem { Label(watchTabTitle, systemImage: "play.rectangle.fill") }
                .tag(1)

            // 2 — Listen
            NavigationStack { ListenView() }
                .tabItem { Label("Listen", systemImage: "headphones") }
                .tag(2)

            // 3 — Read
            NavigationStack { ReadView() }
                .tabItem { Label("Read", systemImage: "book.fill") }
                .tag(3)

            // 4 — Library (playlists)
            NavigationStack { PlaylistsView() }
                .tabItem { Label("My Playlists", systemImage: "bookmark.fill") }
                .tag(4)
        }
        .task {
            while !Task.isCancelled {
                let stream = try? await api.activeLiveStream()
                let assets = (try? await api.fetchAllAssets()) ?? []
                await MainActor.run {
                    LiveStreamManager.shared.update(stream: stream, allAssets: assets, authoritative: true)
                    NewContentTracker.shared.update(assets: assets)
                }
                try? await Task.sleep(nanoseconds: 30_000_000_000)
            }
        }
    }
    #endif
}
