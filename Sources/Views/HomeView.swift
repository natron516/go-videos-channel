import SwiftUI

struct HomeView: View {
    @EnvironmentObject var api: MuxAPI
    @ObservedObject private var autoplay = AutoplayManager.shared
    @ObservedObject private var featured = FeaturedManager.shared
    @ObservedObject private var liveManager = LiveStreamManager.shared
    @ObservedObject private var contentAPI = ContentAPI.shared
    @State private var recentAssets: [MuxAsset] = []
    @State private var allAssets: [MuxAsset] = []
    @State private var liveStream: MuxLiveStream?
    @State private var isLoading = true
    @State private var addToPlaylistAssetId: String?
    @State private var showAddToPlaylist = false
    @State private var showLinkTV = false
    @State private var showAbout = false
    @State private var showWatchTimer = false
    @State private var showSearch = false
    @State private var showLivePinLock = false
    @State private var currentVideoIndex = 1 // starts at 1 because of loop padding

    // Featured content from Firestore
    @State private var featuredAudio: [GOAudioAsset] = []
    @State private var featuredSeries: [GOSeries] = []
    @State private var featuredPodcasts: [GOPodcast] = []
    @State private var featuredBooks: [GOBook] = []
    @State private var featuredArticles: [GOArticle] = []

    /// Assets to display — only when a featured curation list is set.
    /// Empty list hides the video carousel entirely.
    private var displayAssets: [MuxAsset] {
        let ids = featured.featuredIds
        guard !ids.isEmpty else { return [] }
        let lookup = Dictionary(uniqueKeysWithValues: allAssets.map { ($0.id, $0) })
        return ids.compactMap { lookup[$0] }
    }

    private var sectionTitle: String {
        featured.featuredIds.isEmpty ? "Recent Videos" : "Featured"
    }

    private var sectionIcon: String {
        featured.featuredIds.isEmpty ? "play.rectangle.fill" : "star.fill"
    }

    /// Combined featured audio items for the circle scroller
    private var allFeaturedAudio: [FeaturedAudioItem] {
        var items: [FeaturedAudioItem] = []
        for s in featuredSeries {
            items.append(FeaturedAudioItem(id: "series-\(s.id)", title: s.title, imageUrl: s.artworkUrl, kind: .series(s)))
        }
        for p in featuredPodcasts {
            items.append(FeaturedAudioItem(id: "podcast-\(p.id)", title: p.title, imageUrl: p.artworkUrl, kind: .podcast(p)))
        }
        for a in featuredAudio {
            items.append(FeaturedAudioItem(id: "audio-\(a.id)", title: a.title, imageUrl: a.coverImageUrl, kind: .audio(a)))
        }
        return items
    }

    /// Combined featured read items for the square grid
    private var allFeaturedRead: [FeaturedReadItem] {
        var items: [FeaturedReadItem] = []
        for b in featuredBooks {
            items.append(FeaturedReadItem(id: "book-\(b.id)", title: b.title, subtitle: b.author, imageUrl: b.coverImageUrl, kind: .book(b)))
        }
        for a in featuredArticles {
            items.append(FeaturedReadItem(id: "article-\(a.id)", title: a.title, subtitle: a.author, imageUrl: a.coverImageUrl, kind: .article(a)))
        }
        return items
    }

    private var tvOSSpacing: Bool {
        #if os(tvOS)
        return true
        #else
        return false
        #endif
    }

    // Home screen video cards — single column stacked, 25% smaller via padding
    var columns: [GridItem] {
        #if os(tvOS)
        return Array(repeating: GridItem(.flexible(), spacing: 48), count: 3)
        #else
        if UIDevice.current.userInterfaceIdiom == .pad {
            return Array(repeating: GridItem(.flexible(), spacing: 24), count: 3)
        } else {
            return [GridItem(.flexible(), spacing: 0)]
        }
        #endif
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {

                // Logo header
                #if os(tvOS)
                HStack {
                    Image("CrossLogo")
                        .resizable()
                        .scaledToFit()
                        .frame(height: 100)
                    Spacer()
                }
                .padding(.horizontal, 20)
                // padding placeholder removed
                #else
                // Logo lives in the nav bar on iOS — nothing here
                #endif


                if isLoading {
                    VStack(spacing: 20) {
                        ProgressView()
                            .scaleEffect(1.5)
                        Text("Loading…")
                            .font(.callout)
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity, minHeight: 300)
                } else {

                    // ── 🎬 WATCH SECTION (Videos at top) ──
                    if !displayAssets.isEmpty {
                        // Build looping array: [last, 0, 1, ..., n-1, first]
                        let loopAssets: [(index: Int, asset: MuxAsset)] = {
                            let items = displayAssets
                            guard items.count > 1 else { return items.enumerated().map { ($0.offset, $0.element) } }
                            var arr: [(Int, MuxAsset)] = []
                            arr.append((-1, items.last!))           // sentinel: copy of last
                            for (i, a) in items.enumerated() { arr.append((i, a)) }
                            arr.append((items.count, items.first!)) // sentinel: copy of first
                            return arr
                        }()
                        let realCount = displayAssets.count

                        ZStack(alignment: .bottom) {
                            TabView(selection: $currentVideoIndex) {
                                ForEach(Array(loopAssets.enumerated()), id: \.offset) { padIdx, pair in
                                    let asset = pair.asset
                                    VStack(spacing: 6) {
                                        CachedAsyncImage(url: asset.thumbnailURL, fallbackURL: asset.fallbackThumbnailURL) {
                                            Rectangle()
                                                .fill(Color.gray.opacity(0.3))
                                                .overlay(Image(systemName: "play.circle").font(.largeTitle).foregroundColor(.white))
                                        }
                                        .aspectRatio(16.0/9.0, contentMode: .fill)
                                        .frame(maxWidth: .infinity)
                                        .clipped()
                                        .clipShape(RoundedRectangle(cornerRadius: 8))
                                        .overlay(alignment: .bottom) {
                                            LinearGradient(
                                                colors: [Color.clear, Color(red: 0.075, green: 0.075, blue: 0.075)],
                                                startPoint: .top,
                                                endPoint: .bottom
                                            )
                                            .frame(height: UIScreen.main.bounds.width * 9.0/16.0 * 0.35)
                                            .clipShape(RoundedRectangle(cornerRadius: 8))
                                        }

                                        Text(asset.title)
                                            .font(.subheadline.bold())
                                            .foregroundColor(.white)
                                            .lineLimit(2)
                                            .multilineTextAlignment(.center)
                                            .frame(maxWidth: .infinity)
                                    }
                                    .contentShape(Rectangle())
                                    .onTapGesture {
                                        if let url = asset.streamURL {
                                            AutoplayManager.shared.setContext(asset: asset, playlist: displayAssets)
                                            presentPlayer(url: url)
                                        }
                                    }
                                    .contextMenu {
                                        Button {
                                            addToPlaylistAssetId = asset.id
                                            showAddToPlaylist = true
                                        } label: {
                                            Label("Add to Playlist", systemImage: "plus.circle")
                                        }
                                        #if !os(tvOS)
                                        if let url = asset.shareURL ?? asset.streamURL {
                                            ShareLink(
                                                item: url,
                                                subject: Text(asset.title),
                                                message: Text("Watch \(asset.title) on GO Videos")
                                            ) {
                                                Label("Share", systemImage: "square.and.arrow.up")
                                            }
                                        }
                                        #endif
                                    }
                                    .tag(padIdx)
                                }
                            }
                            .tabViewStyle(.page(indexDisplayMode: .never))
                            .frame(height: UIScreen.main.bounds.width * 9.0/16.0 + 40)
                            .onChange(of: currentVideoIndex) { newVal in
                                // Wrap around for infinite loop
                                if realCount > 1 {
                                    if newVal == 0 {
                                        // Swiped left past first → jump to real last
                                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                                            withAnimation(.none) { currentVideoIndex = realCount }
                                        }
                                    } else if newVal == realCount + 1 {
                                        // Swiped right past last → jump to real first
                                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                                            withAnimation(.none) { currentVideoIndex = 1 }
                                        }
                                    }
                                }
                            }

                            // Page indicator dots (mapped to real indices)
                            if realCount > 1 {
                                let dotIndex = max(0, min(realCount - 1, currentVideoIndex - 1))
                                HStack(spacing: 6) {
                                    ForEach(0..<realCount, id: \.self) { i in
                                        Circle()
                                            .fill(i == dotIndex ? Color.white : Color.white.opacity(0.35))
                                            .frame(width: 8, height: 8)
                                    }
                                }
                                .padding(.bottom, 30)
                            }
                        }
                    }

                    // ── 🎧 LISTEN SECTION (Audio — circular thumbnails, horizontal scroll) ──
                    if !allFeaturedAudio.isEmpty {
                        VStack(alignment: .leading, spacing: 12) {

                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: tvOSSpacing ? 28 : 16) {
                                    ForEach(allFeaturedAudio) { item in
                                        featuredAudioCircle(item: item)
                                    }
                                }
                                .padding(.horizontal, tvOSSpacing ? 20 : 16)
                            }
                        }
                        .padding(.top, 24)
                    }

                    // ── 📖 READ SECTION (Books/Articles — square thumbnails, horizontal scroll) ──
                    if !allFeaturedRead.isEmpty {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 14) {
                                ForEach(allFeaturedRead) { item in
                                    featuredReadSquare(item: item)
                                        .frame(width: 96)
                                }
                            }
                            .padding(.horizontal, 16)
                        }
                        .padding(.top, 24)
                    }
                }
            }
            .padding(.vertical, 20)
        }
        #if !os(tvOS)
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.hidden, for: .navigationBar)
        .goNavBar(showLinkTV: $showLinkTV, showWatchTimer: $showWatchTimer, showSearch: $showSearch)
        .sheet(isPresented: $showLinkTV) { LinkTVView() }
        .sheet(isPresented: $showSearch) { NavigationStack { SearchView() } }
        #endif
        .sheet(isPresented: $showWatchTimer) { WatchTimerSetupView() }
        .appBackground()
        .task { await load() }
        .addToPlaylistPresentation(isPresented: $showAddToPlaylist, assetId: addToPlaylistAssetId)
        #if os(tvOS)
        // fullScreenCover gives the PIN proper focus ownership on tvOS
        .fullScreenCover(isPresented: $showLivePinLock) {
            PinLockView {
                showLivePinLock = false
                playLiveAsset()
            }
        }
        #else
        .overlay {
            if showLivePinLock {
                PinLockView {
                    showLivePinLock = false
                    playLiveAsset()
                }
                .ignoresSafeArea()
            }
        }
        #endif
    }

    // MARK: - Featured Audio Circle

    @ViewBuilder
    func featuredAudioCircle(item: FeaturedAudioItem) -> some View {
        let circleSize: CGFloat = {
            #if os(tvOS)
            return 200
            #else
            return UIDevice.current.userInterfaceIdiom == .pad ? 184 : 150
            #endif
        }()

        Group {
            switch item.kind {
            case .series(let series):
                NavigationLink(destination: SeriesDetailView(series: series)) {
                    audioCircleContent(title: item.title, imageUrl: item.imageUrl, size: circleSize, icon: "music.note.list")
                }
            case .podcast(let podcast):
                NavigationLink(destination: PodcastDetailView(podcast: podcast)) {
                    audioCircleContent(title: item.title, imageUrl: item.imageUrl, size: circleSize, icon: "mic.fill")
                }
            case .audio(let audio):
                Button {
                    AudioPlayerManager.shared.play(url: audio.audioUrl, title: audio.title, artist: audio.artist, coverUrl: audio.coverImageUrl, trackId: audio.id, resumeAt: PlaybackTracker.shared.getPosition(audio.id))
                } label: {
                    audioCircleContent(title: item.title, imageUrl: item.imageUrl, size: circleSize, icon: "waveform")
                }
            }
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    func audioCircleContent(title: String, imageUrl: String?, size: CGFloat, icon: String) -> some View {
        VStack(spacing: 8) {
            ZStack {
                if let urlStr = imageUrl, let url = URL(string: urlStr) {
                    CachedAsyncImage(url: url) {
                        Circle()
                            .fill(Color.white.opacity(0.08))
                            .overlay(
                                Image(systemName: icon)
                                    .font(.system(size: size * 0.25))
                                    .foregroundColor(.secondary)
                            )
                    }
                    .frame(width: size, height: size)
                    .clipShape(Circle())
                } else {
                    Circle()
                        .fill(Color.white.opacity(0.08))
                        .frame(width: size, height: size)
                        .overlay(
                            Image(systemName: icon)
                                .font(.system(size: size * 0.25))
                                .foregroundColor(.secondary)
                        )
                }
            }
            .overlay(
                Circle()
                    .stroke(Color.white.opacity(0.15), lineWidth: 1)
            )

            Text(title)
                .font(.caption.bold())
                .foregroundColor(.white)
                .lineLimit(2)
                .multilineTextAlignment(.center)
                .frame(width: size)

            // Subtle headphone badge under the circle
            Text("♫")
                .font(.system(size: 10))
                .foregroundColor(.white.opacity(0.4))
        }
    }

    // MARK: - Featured Read Square

    @ViewBuilder
    func featuredReadSquare(item: FeaturedReadItem) -> some View {
        Group {
            switch item.kind {
            case .book(let book):
                #if os(tvOS)
                readSquareContent(title: item.title, subtitle: item.subtitle, imageUrl: item.imageUrl, icon: "book.fill")
                #else
                NavigationLink(destination: BookDetailView(book: book)) {
                    readSquareContent(title: item.title, subtitle: item.subtitle, imageUrl: item.imageUrl, icon: "book.fill")
                }
                #endif
            case .article(let article):
                #if os(tvOS)
                readSquareContent(title: item.title, subtitle: item.subtitle, imageUrl: item.imageUrl, icon: "doc.text.fill")
                #else
                NavigationLink(destination: ArticleDetailView(article: article)) {
                    readSquareContent(title: item.title, subtitle: item.subtitle, imageUrl: item.imageUrl, icon: "doc.text.fill")
                }
                #endif
            }
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    func readSquareContent(title: String, subtitle: String, imageUrl: String?, icon: String) -> some View {
        VStack(spacing: 0) {
            ZStack(alignment: .topTrailing) {
                if let urlStr = imageUrl, let url = URL(string: urlStr) {
                    Color.clear
                        .aspectRatio(2.0/3.0, contentMode: .fit)
                        .overlay(
                            CachedAsyncImage(url: url) {
                                RoundedRectangle(cornerRadius: 10)
                                    .fill(Color.white.opacity(0.08))
                                    .overlay(
                                        Image(systemName: icon)
                                            .font(.system(size: 30))
                                            .foregroundColor(.secondary)
                                    )
                            }
                            .scaledToFill()
                        )
                        .clipped()
                        .cornerRadius(10)
                } else {
                    RoundedRectangle(cornerRadius: 10)
                        .fill(Color.white.opacity(0.08))
                        .aspectRatio(2.0/3.0, contentMode: .fit)
                        .overlay(
                            Image(systemName: icon)
                                .font(.system(size: 30))
                                .foregroundColor(.secondary)
                        )
                }

                // Page corner fold (dogear)
                PageCornerFold()
                }
            }
        }

    // MARK: - Live Now

    @ViewBuilder
    func liveNowBanner(stream: MuxLiveStream) -> some View {
        Button {
            if PinUnlockManager.shared.isUnlocked {
                playLiveAsset()
            } else {
                showLivePinLock = true
            }
        } label: {
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 12)
                    .fill(LinearGradient(colors: [.red, .red.opacity(0.6)], startPoint: .leading, endPoint: .trailing))
                    .frame(maxWidth: .infinity, minHeight: 56)
                HStack(spacing: 12) {
                    Circle().fill(Color.white)
                        .frame(width: 12, height: 12)
                    Text("LIVE NOW  —  \(stream.title)")
                        .font(.headline.bold())
                        .foregroundColor(.white)
                        .lineLimit(1)
                }
                .padding(.horizontal, 20)
            }
        }
        .mediaCardStyle()
    }

    func playLiveAsset() {
        // Use the preparing asset URL (same as clicking it in SermonLibraryView)
        if let asset = liveManager.liveAsset, let url = asset.streamURL {
            AutoplayManager.shared.setContext(asset: asset, playlist: [asset])
            presentPlayer(url: url, asset: asset)
        } else if let url = liveStream?.streamURL {
            // Fallback: use live stream URL directly
            presentPlayer(url: url)
        } else {
            AppNavigator.goToSermons()
        }
    }

    func load() async {
        // Wait for splash preloader if it's still running (avoid duplicate network calls)
        let pre = ContentPreloader.shared
        if pre.isPreloading && !pre.isComplete {
            // Wait up to 8s for preloader
            for _ in 0..<80 {
                if pre.isComplete { break }
                try? await Task.sleep(nanoseconds: 100_000_000)
            }
        }

        // If cache has assets, show them immediately (no spinner)
        if let cached = api.cachedAssets, !cached.isEmpty {
            let filtered = cached.filter { $0.status == "ready" || $0.status == "preparing" }
                .filter { $0.category != nil && $0.category != "hidden" }
            if !filtered.isEmpty {
                allAssets = cached.filter { $0.status == "ready" || $0.status == "preparing" }
                recentAssets = filtered.filter { $0.category != "sermon" }
                isLoading = false
            }
        }
        if recentAssets.isEmpty { isLoading = true }

        // Load video assets + live stream
        async let assets = api.fetchAssets()
        async let live = api.activeLiveStream()

        // Only fetch featured if not already loaded by preloader
        if !FeaturedManager.shared.isLoaded {
            async let _ = FeaturedManager.shared.fetch()
        }

        // Load featured content from other content types (pre already declared above)
        async let audioResult: [GOAudioAsset] = {
            if let cached = pre.audioAssets { return cached }
            return (try? await contentAPI.fetchAudio()) ?? []
        }()
        async let seriesResult: [GOSeries] = {
            if let cached = pre.series { return cached }
            return (try? await contentAPI.fetchSeries()) ?? []
        }()
        async let podcastsResult: [GOPodcast] = {
            if let cached = pre.podcasts { return cached }
            return (try? await contentAPI.fetchPodcasts()) ?? []
        }()
        async let booksResult: [GOBook] = {
            if let cached = pre.books { return cached }
            return (try? await contentAPI.fetchBooks()) ?? []
        }()
        async let articlesResult: [GOArticle] = {
            if let cached = pre.articles { return cached }
            return (try? await contentAPI.fetchArticles()) ?? []
        }()

        let fetched = (try? await assets) ?? []
        allAssets = fetched
        recentAssets = fetched.filter { $0.category != "sermon" && $0.category != "hidden" }
        liveStream = try? await live
        LiveStreamManager.shared.update(stream: liveStream, allAssets: fetched)
        NewContentTracker.shared.update(assets: fetched)

        // Filter featured content
        let allAudio = await audioResult
        let allSeries = await seriesResult
        let allPodcasts = await podcastsResult
        let allBooks = await booksResult
        let allArticles = await articlesResult

        featuredAudio = allAudio.filter { $0.featured }
        featuredSeries = allSeries.filter { $0.featured }
        featuredPodcasts = allPodcasts.filter { $0.featured }
        featuredBooks = allBooks.filter { $0.featured }
        featuredArticles = allArticles.filter { $0.featured }

        prefetchThumbnails(displayAssets.map(\.thumbnailURL))
        isLoading = false
    }
}

// MARK: - Featured Audio Item

struct FeaturedAudioItem: Identifiable {
    let id: String
    let title: String
    let imageUrl: String?
    let kind: Kind

    enum Kind {
        case series(GOSeries)
        case podcast(GOPodcast)
        case audio(GOAudioAsset)
    }
}

// MARK: - Featured Read Item

struct FeaturedReadItem: Identifiable {
    let id: String
    let title: String
    let subtitle: String
    let imageUrl: String?
    let kind: Kind

    enum Kind {
        case book(GOBook)
        case article(GOArticle)
    }
}

// MARK: - Page Corner Fold (dogear effect)

struct PageCornerFold: View {
    var size: CGFloat = 22

    var body: some View {
        Canvas { context, canvasSize in
            // Clip triangle in top-right corner
            let foldPath = Path { p in
                p.move(to: CGPoint(x: canvasSize.width - size, y: 0))
                p.addLine(to: CGPoint(x: canvasSize.width, y: 0))
                p.addLine(to: CGPoint(x: canvasSize.width, y: size))
                p.closeSubpath()
            }
            // Dark triangle to "cut" the corner
            context.fill(foldPath, with: .color(Color(red: 0.075, green: 0.075, blue: 0.075)))

            // Fold triangle (the turned page)
            let fold = Path { p in
                p.move(to: CGPoint(x: canvasSize.width - size, y: 0))
                p.addLine(to: CGPoint(x: canvasSize.width, y: size))
                p.addLine(to: CGPoint(x: canvasSize.width - size, y: size))
                p.closeSubpath()
            }
            context.fill(fold, with: .color(Color.white.opacity(0.25)))

            // Subtle shadow line along fold
            let shadow = Path { p in
                p.move(to: CGPoint(x: canvasSize.width - size, y: 0))
                p.addLine(to: CGPoint(x: canvasSize.width, y: size))
            }
            context.stroke(shadow, with: .color(Color.black.opacity(0.3)), lineWidth: 1)
        }
        .allowsHitTesting(false)
    }
}
