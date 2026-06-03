import SwiftUI

#if !os(tvOS)

enum ReadSegment: String, CaseIterable {
    case books = "Books"
    case articles = "Articles"
}

struct ReadView: View {
    @State private var segment: ReadSegment = .books
    @State private var showLinkTV = false
    @State private var showWatchTimer = false
    @State private var showSearch = false

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            Color.clear.appBackground()

            VStack(spacing: 0) {
                // Segment picker
                Picker("Read", selection: $segment) {
                    ForEach(ReadSegment.allCases, id: \.self) { seg in
                        Text(seg.rawValue).tag(seg)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, 16)
                .padding(.top, 12)
                .padding(.bottom, 8)

                Divider().background(Color.white.opacity(0.1))

                switch segment {
                case .books:
                    BookListView()
                case .articles:
                    ArticleListView()
                }
            }
        }
        .navigationTitle("Read")
        .goNavBar(showLinkTV: $showLinkTV, showWatchTimer: $showWatchTimer, showSearch: $showSearch)
        .sheet(isPresented: $showLinkTV) { LinkTVView() }
        .sheet(isPresented: $showSearch) { NavigationStack { SearchView() } }
        .sheet(isPresented: $showWatchTimer) { WatchTimerSetupView() }
    }
}

#endif
