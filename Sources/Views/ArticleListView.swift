import SwiftUI

#if !os(tvOS)

struct ArticleListView: View {
    var searchText: String = ""
    @ObservedObject private var contentAPI = ContentAPI.shared
    @State private var articles: [GOArticle] = []
    @State private var isLoading = true
    @State private var showAddToPlaylist = false
    @State private var addToPlaylistArticleId: String?
    @State private var error: String?
    @State private var selectedCategories: Set<String> = []

    private var articleCategories: [(value: String, label: String)] {
        let cats = Set(articles.map { $0.category }).sorted()
        return cats.map { cat in
            (cat, cat.replacingOccurrences(of: "-", with: " ").capitalized)
        }
    }

    var columns: [GridItem] {
        if UIDevice.current.userInterfaceIdiom == .pad {
            return Array(repeating: GridItem(.flexible(), spacing: 14), count: 6)
        }
        return Array(repeating: GridItem(.flexible(), spacing: 10), count: 3)
    }

    var body: some View {
        ZStack {
            Color.clear
            if let err = error {
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
            } else if !isLoading && articles.isEmpty {
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
                    VStack(spacing: 16) {
                        // Category pill bar (multiselect — empty = All)
                        if articleCategories.count > 1 {
                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: 8) {
                                    ForEach(articleCategories, id: \.value) { cat in
                                        Button {
                                            withAnimation(.easeInOut(duration: 0.2)) {
                                                if selectedCategories.contains(cat.value) {
                                                    selectedCategories.remove(cat.value)
                                                } else {
                                                    selectedCategories.insert(cat.value)
                                                }
                                            }
                                        } label: {
                                            Text(cat.label)
                                                .font(.subheadline.weight(.semibold))
                                                .padding(.horizontal, 14)
                                                .padding(.vertical, 7)
                                                .background(
                                                    Capsule().fill(
                                                        selectedCategories.contains(cat.value)
                                                            ? Color.blue
                                                            : Color.white.opacity(0.1)
                                                    )
                                                )
                                                .foregroundColor(
                                                    selectedCategories.contains(cat.value) ? .white : .secondary
                                                )
                                        }
                                    }
                                }
                                .padding(.horizontal, 16)
                            }
                        }

                    LazyVGrid(columns: columns, spacing: 14) {
                        ForEach(filteredArticles) { article in
                            NavigationLink {
                                ArticleDetailView(article: article)
                            } label: {
                                ArticleCard(article: article)
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
                    .padding(.horizontal, 16)
                    }
                    .padding(.vertical, 12)
                }
            }
        }
        .overlay {
            if isLoading {
                ProgressView("Loading…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color.black.opacity(0.3))
            }
        }
        .task { await load() }
        .addToPlaylistPresentation(isPresented: $showAddToPlaylist, mediaType: "article", mediaId: addToPlaylistArticleId)
    }

    private var filteredArticles: [GOArticle] {
        var result = selectedCategories.isEmpty ? articles : articles.filter { selectedCategories.contains($0.category) }
        if !searchText.isEmpty {
            let q = searchText.lowercased()
            result = result.filter { $0.title.lowercased().contains(q) || $0.author.lowercased().contains(q) }
        }
        return result
    }

    private func load() async {
        if let cached = ContentPreloader.shared.articles {
            articles = cached
            isLoading = false
            return
        }
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

// MARK: - Article Card (half-height book card style)
struct ArticleCard: View {
    let article: GOArticle

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            // Cover image — 3:2 landscape aspect (half the height of book cards' 2:3)
            Group {
                if let urlStr = article.coverImageUrl, let url = URL(string: urlStr) {
                    CachedAsyncImage(url: url) {
                        Color.white.opacity(0.08)
                            .overlay(
                                Image(systemName: "doc.text.fill")
                                    .font(.system(size: 24))
                                    .foregroundColor(.secondary)
                            )
                    }
                } else {
                    Color.white.opacity(0.08)
                        .overlay(
                            Image(systemName: "doc.text.fill")
                                .font(.system(size: 24))
                                .foregroundColor(.secondary)
                        )
                }
            }
            .aspectRatio(3.0/2.0, contentMode: .fit)
            .clipped()
            .cornerRadius(8)
            .shadow(color: .black.opacity(0.5), radius: 4, x: 0, y: 2)

            VStack(alignment: .leading, spacing: 2) {
                Text(article.title)
                    .font(.caption.bold())
                    .foregroundColor(.white)
                    .lineLimit(2)
                Text(article.author)
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }
        }
    }
}

// MARK: - Article Row (for playlist/list contexts)
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
            if let urlStr = article.coverImageUrl, let url = URL(string: urlStr) {
                CachedAsyncImage(url: url) {
                    Color.white.opacity(0.08)
                }
                .frame(width: 80, height: 54)
                .clipped()
                .cornerRadius(8)
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
    }
}

#endif
