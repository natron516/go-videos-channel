import SwiftUI

#if !os(tvOS)

struct ArticleListView: View {
    @ObservedObject private var contentAPI = ContentAPI.shared
    @State private var articles: [GOArticle] = []
    @State private var isLoading = true
    @State private var showAddToPlaylist = false
    @State private var addToPlaylistArticleId: String?
    @State private var error: String?

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            Color.clear.appBackground()

            if isLoading {
                ProgressView("Loading Articles…")
            } else if let err = error {
                VStack(spacing: 16) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.system(size: 50))
                        .foregroundColor(.orange)
                    Text("Unable to load articles")
                        .font(.title3)
                    Text(err)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                    Button("Retry") { Task { await load() } }
                        .buttonStyle(.borderedProminent)
                }
                .padding(40)
            } else if articles.isEmpty {
                VStack(spacing: 16) {
                    Image(systemName: "doc.text")
                        .font(.system(size: 50))
                        .foregroundColor(.secondary)
                    Text("No Articles Yet")
                        .font(.title3)
                        .foregroundColor(.secondary)
                }
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(articles) { article in
                            NavigationLink {
                                ArticleDetailView(article: article)
                            } label: {
                                ArticleRow(article: article)
                            }
                            .buttonStyle(.plain)
                            .contextMenu {
                                Button {
                                    addToPlaylistArticleId = article.id
                                    showAddToPlaylist = true
                                } label: {
                                    Label("Add to Playlist", systemImage: "text.badge.plus")
                                }
                            }
                        }
                    }
                    .padding(.vertical, 8)
                }
            }
        }
        .task { await load() }
        .addToPlaylistPresentation(isPresented: $showAddToPlaylist, mediaType: "article", mediaId: addToPlaylistArticleId)
    }

    private func load() async {
        isLoading = true
        error = nil
        do {
            articles = try await contentAPI.fetchArticles()
        } catch {
            self.error = error.localizedDescription
        }
        isLoading = false
    }
}

// MARK: - Article Row
struct ArticleRow: View {
    let article: GOArticle

    private var formattedDate: String {
        guard let date = article.createdAt else { return "" }
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        return formatter.string(from: date)
    }

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            // Cover image if available
            if let urlStr = article.coverImageUrl, let url = URL(string: urlStr) {
                CachedAsyncImage(url: url) {
                    Color.white.opacity(0.08)
                }
                .frame(width: 80, height: 80)
                .clipped()
                .cornerRadius(10)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(article.title)
                    .font(.headline)
                    .foregroundColor(.white)
                    .lineLimit(2)

                if !article.excerpt.isEmpty {
                    Text(article.excerpt)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(2)
                }

                HStack(spacing: 8) {
                    Text(article.author)
                        .font(.caption2.bold())
                        .foregroundColor(.secondary)
                    if !formattedDate.isEmpty {
                        Text("·")
                            .foregroundColor(.secondary)
                        Text(formattedDate)
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }
            }
            Spacer()
            Image(systemName: "chevron.right")
                .foregroundColor(.secondary)
                .font(.caption)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
        .background(Color.white.opacity(0.02))
        .overlay(
            Divider().background(Color.white.opacity(0.07)),
            alignment: .bottom
        )
    }
}

#endif
