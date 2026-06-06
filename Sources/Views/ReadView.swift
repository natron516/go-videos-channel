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
    @State private var searchText = ""

    var body: some View {
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

            // Search bar
            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(.secondary)
                TextField("Search \(segment.rawValue.lowercased())...", text: $searchText)
                    .foregroundColor(.white)
                    .autocorrectionDisabled()
                if !searchText.isEmpty {
                    Button { searchText = "" } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.secondary)
                    }
                }
            }
            .padding(10)
            .background(Color.white.opacity(0.08))
            .cornerRadius(10)
            .padding(.horizontal, 16)
            .padding(.bottom, 8)

            Divider().background(Color.white.opacity(0.1))

            Group {
                switch segment {
                case .books:
                    BookListView(searchText: searchText)
                case .articles:
                    ArticleListView(searchText: searchText)
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
