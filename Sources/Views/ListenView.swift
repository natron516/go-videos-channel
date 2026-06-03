import SwiftUI

#if !os(tvOS)

enum ListenSegment: String, CaseIterable {
    case music = "Music"
    case podcasts = "Podcasts"
    case audio = "Audio"
}

struct ListenView: View {
    @State private var segment: ListenSegment = .music
    @State private var showLinkTV = false
    @State private var showWatchTimer = false
    @State private var showSearch = false

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            Color.clear.appBackground()

            VStack(spacing: 0) {
                // Segment picker
                Picker("Listen", selection: $segment) {
                    ForEach(ListenSegment.allCases, id: \.self) { seg in
                        Text(seg.rawValue).tag(seg)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, 16)
                .padding(.top, 12)
                .padding(.bottom, 8)

                Divider().background(Color.white.opacity(0.1))

                // Content
                switch segment {
                case .music:
                    AppleMusicView()
                case .podcasts:
                    PodcastListView()
                case .audio:
                    AudioListView()
                }
            }
        }
        .navigationTitle("Listen")
        .goNavBar(showLinkTV: $showLinkTV, showWatchTimer: $showWatchTimer, showSearch: $showSearch)
        .sheet(isPresented: $showLinkTV) { LinkTVView() }
        .sheet(isPresented: $showSearch) { NavigationStack { SearchView() } }
        .sheet(isPresented: $showWatchTimer) { WatchTimerSetupView() }
    }
}

#endif
