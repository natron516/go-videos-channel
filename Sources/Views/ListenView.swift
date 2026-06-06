import SwiftUI

#if !os(tvOS)

enum ListenSegment: String, CaseIterable {
    case music = "Music"
    case podcasts = "Podcasts"
    case audio = "Audiobooks"
}

struct ListenView: View {
    @State private var segment: ListenSegment = .music
    @State private var showLinkTV = false
    @State private var showWatchTimer = false
    @State private var showSearch = false

    var body: some View {
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
            Group {
                switch segment {
                case .music:
                    AppleMusicView()
                case .podcasts:
                    PodcastListView()
                case .audio:
                    AudioListView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .appBackground()
        .navigationTitle("")
        .goNavBar(showLinkTV: $showLinkTV, showWatchTimer: $showWatchTimer, showSearch: $showSearch)
        .sheet(isPresented: $showLinkTV) { LinkTVView() }
        .sheet(isPresented: $showSearch) { NavigationStack { SearchView() } }
        .sheet(isPresented: $showWatchTimer) { WatchTimerSetupView() }
    }
}

#endif
