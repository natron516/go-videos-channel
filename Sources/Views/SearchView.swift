import SwiftUI
import MusicKit

struct SearchView: View {
    @EnvironmentObject var api: MuxAPI
    @StateObject private var music = AppleMusicService.shared
    @State private var allAssets: [MuxAsset] = []
    @State private var query = ""
    @State private var allBooks: [GOBook] = []
    @State private var allArticles: [GOArticle] = []

    var results: [MuxAsset] {
        guard !query.isEmpty else { return [] }
        let q = query.lowercased()
        return allAssets.filter {
            $0.title.lowercased().contains(q) ||
            ($0.speaker?.lowercased().contains(q) ?? false)
        }
    }

    var bookResults: [GOBook] {
        guard !query.isEmpty else { return [] }
        let q = query.lowercased()
        return allBooks.filter {
            $0.title.lowercased().contains(q) ||
            $0.author.lowercased().contains(q)
        }
    }

    var articleResults: [GOArticle] {
        guard !query.isEmpty else { return [] }
        let q = query.lowercased()
        return allArticles.filter {
            $0.title.lowercased().contains(q) ||
            $0.author.lowercased().contains(q)
        }
    }

    var musicResults: [Album] {
        guard !query.isEmpty, music.isAuthorized else { return [] }
        let q = query.lowercased()
        return music.curatedAlbums.filter {
            $0.title.lowercased().contains(q) ||
            $0.artistName.lowercased().contains(q)
        }
    }

    var columns: [GridItem] {
        #if os(tvOS)
        return Array(repeating: GridItem(.flexible(), spacing: 40), count: 4)
        #else
        return [GridItem(.adaptive(minimum: 160))]
        #endif
    }

    var body: some View {
        VStack(spacing: 0) {
            // Search field
            HStack {
                Image(systemName: "magnifyingglass").foregroundColor(.secondary)
                TextField("Search videos, books, music…", text: $query)
                    .font(.title3)
                if !query.isEmpty {
                    Button { query = "" } label: {
                        Image(systemName: "xmark.circle.fill").foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding()
            .background(Color.gray.opacity(0.15))
            .cornerRadius(12)
            .padding(.horizontal, 16)
            .padding(.vertical, 10)

            // Results
            ScrollView {
                if query.isEmpty {
                    VStack(spacing: 16) {
                        Image(systemName: "magnifyingglass")
                            .font(.system(size: 60))
                            .foregroundColor(.secondary)
                        Text("Type to search videos & music")
                            .font(.title2).foregroundColor(.secondary)
                    }
                    .padding(.top, 60)
                } else if results.isEmpty && musicResults.isEmpty && bookResults.isEmpty && articleResults.isEmpty {
                    Text("No results for \"\(query)\"")
                        .font(.title2).foregroundColor(.secondary)
                        .padding(.top, 60)
                } else {
                    VStack(alignment: .leading, spacing: 14) {
                        // Music results
                        if !musicResults.isEmpty {
                            Text("Music")
                                .font(.subheadline.bold())
                                .foregroundColor(.white)
                                .padding(.horizontal, 16)

                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: 12) {
                                    ForEach(musicResults) { album in
                                        NavigationLink(destination: AlbumDetailView(album: album)) {
                                            VStack(spacing: 8) {
                                                if let artwork = album.artwork {
                                                    ArtworkImage(artwork, width: 120)
                                                        .aspectRatio(1, contentMode: .fit)
                                                        .clipShape(RoundedRectangle(cornerRadius: 10))
                                                } else {
                                                    RoundedRectangle(cornerRadius: 10)
                                                        .fill(Color.gray.opacity(0.3))
                                                        .frame(width: 120, height: 120)
                                                        .overlay(
                                                            Image(systemName: "music.note")
                                                                .foregroundColor(.white.opacity(0.4))
                                                        )
                                                }
                                                Text(album.title)
                                                    .font(.caption.bold())
                                                    .foregroundColor(.white)
                                                    .lineLimit(2)
                                                    .multilineTextAlignment(.center)
                                                    .frame(width: 120)
                                                Text(album.artistName)
                                                    .font(.caption2)
                                                    .foregroundColor(.secondary)
                                                    .lineLimit(1)
                                            }
                                        }
                                        .buttonStyle(.plain)
                                    }
                                }
                                .padding(.horizontal, 16)
                            }
                        }

                        // Book results
                        if !bookResults.isEmpty {
                            Text("Books")
                                .font(.subheadline.bold())
                                .foregroundColor(.white)
                                .padding(.horizontal, 16)

                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: 12) {
                                    ForEach(bookResults) { book in
                                        NavigationLink(destination: BookDetailView(book: book)) {
                                            VStack(spacing: 6) {
                                                if let urlStr = book.coverImageUrl, let url = URL(string: urlStr) {
                                                    CachedAsyncImage(url: url) {
                                                        RoundedRectangle(cornerRadius: 8)
                                                            .fill(Color.gray.opacity(0.3))
                                                            .frame(width: 90, height: 130)
                                                    }
                                                    .frame(width: 90, height: 130)
                                                    .clipShape(RoundedRectangle(cornerRadius: 8))
                                                } else {
                                                    RoundedRectangle(cornerRadius: 8)
                                                        .fill(Color.gray.opacity(0.3))
                                                        .frame(width: 90, height: 130)
                                                        .overlay(Image(systemName: "book.fill").foregroundColor(.white.opacity(0.4)))
                                                }
                                                Text(book.title)
                                                    .font(.caption.bold())
                                                    .foregroundColor(.white)
                                                    .lineLimit(2)
                                                    .frame(width: 90)
                                            }
                                        }
                                        .buttonStyle(.plain)
                                    }
                                }
                                .padding(.horizontal, 16)
                            }
                        }

                        // Article results
                        if !articleResults.isEmpty {
                            Text("Articles")
                                .font(.subheadline.bold())
                                .foregroundColor(.white)
                                .padding(.horizontal, 16)

                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: 12) {
                                    ForEach(articleResults) { article in
                                        NavigationLink(destination: ArticleDetailView(article: article)) {
                                            VStack(spacing: 6) {
                                                if let urlStr = article.coverImageUrl, let url = URL(string: urlStr) {
                                                    CachedAsyncImage(url: url) {
                                                        RoundedRectangle(cornerRadius: 8)
                                                            .fill(Color.gray.opacity(0.3))
                                                            .frame(width: 90, height: 130)
                                                    }
                                                    .frame(width: 90, height: 130)
                                                    .clipShape(RoundedRectangle(cornerRadius: 8))
                                                } else {
                                                    RoundedRectangle(cornerRadius: 8)
                                                        .fill(Color.gray.opacity(0.3))
                                                        .frame(width: 90, height: 130)
                                                        .overlay(Image(systemName: "doc.text.fill").foregroundColor(.white.opacity(0.4)))
                                                }
                                                Text(article.title)
                                                    .font(.caption.bold())
                                                    .foregroundColor(.white)
                                                    .lineLimit(2)
                                                    .frame(width: 90)
                                            }
                                        }
                                        .buttonStyle(.plain)
                                    }
                                }
                                .padding(.horizontal, 16)
                            }
                        }

                        // Video results
                        if !results.isEmpty {
                            Text("Videos")
                                .font(.subheadline.bold())
                                .foregroundColor(.white)
                                .padding(.horizontal, 16)

                            LazyVGrid(columns: columns, spacing: 14) {
                                ForEach(results) { asset in
                                    Button {
                                        if let url = asset.streamURL { presentPlayer(url: url) }
                                    } label: {
                                        SermonCardView(asset: asset)
                                    }
                                    .mediaCardStyle()
                                }
                            }
                            .padding(.horizontal, 16)
                        }
                    }
                    .padding(.top, 4)
                }
            }
        }
        .navigationTitle("Search")
        #if !os(tvOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .navigationBarBackButtonHidden(true)
        .task {
            let contentAPI = ContentAPI.shared
            let pre = ContentPreloader.shared
            async let assetsTask = api.fetchAssets()
            async let booksTask: [GOBook] = {
                if let cached = pre.books { return cached }
                return (try? await contentAPI.fetchBooks()) ?? []
            }()
            async let articlesTask: [GOArticle] = {
                if let cached = pre.articles { return cached }
                return (try? await contentAPI.fetchArticles()) ?? []
            }()
            allAssets = (try? await assetsTask) ?? []
            allBooks = await booksTask
            allArticles = await articlesTask
            if music.isAuthorized && music.curatedAlbums.isEmpty {
                await music.loadCuratedAlbums(ids: CuratedMusic.albumIDs)
            }
        }
    }
}
