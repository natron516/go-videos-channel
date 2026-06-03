import SwiftUI

#if !os(tvOS)

struct BookListView: View {
    @ObservedObject private var contentAPI = ContentAPI.shared
    @State private var allBooks: [GOBook] = []
    @State private var isLoading = true
    @State private var error: String?
    @State private var selectedCategory = "all"
    @State private var showAddToPlaylist = false
    @State private var addToPlaylistBookId: String?

    private let categories: [(value: String, label: String)] = [
        ("all", "All"),
        ("books-for-boys", "Books for Boys"),
        ("books-for-girls", "Books for Girls"),
        ("theology", "Theology"),
        ("books-for-mothers", "Books for Mothers"),
    ]

    private var filteredBooks: [GOBook] {
        if selectedCategory == "all" { return allBooks }
        return allBooks.filter { $0.category == selectedCategory }
    }

    var columns: [GridItem] {
        UIDevice.current.userInterfaceIdiom == .pad
            ? Array(repeating: GridItem(.flexible(), spacing: 20), count: 4)
            : Array(repeating: GridItem(.flexible(), spacing: 10), count: 3)
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            Color.clear.appBackground()

            if isLoading {
                ProgressView("Loading Books…")
            } else if let err = error {
                VStack(spacing: 16) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.system(size: 50))
                        .foregroundColor(.orange)
                    Text("Unable to load books")
                        .font(.title3)
                    Text(err)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                    Button("Retry") { Task { await load() } }
                        .buttonStyle(.borderedProminent)
                }
                .padding(40)
            } else if allBooks.isEmpty {
                VStack(spacing: 16) {
                    Image(systemName: "book.fill")
                        .font(.system(size: 50))
                        .foregroundColor(.secondary)
                    Text("No Books Yet")
                        .font(.title3)
                        .foregroundColor(.secondary)
                }
            } else {
                ScrollView {
                    VStack(spacing: 16) {
                        // Category pill bar
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 8) {
                                ForEach(categories, id: \.value) { cat in
                                    Button {
                                        withAnimation(.easeInOut(duration: 0.2)) {
                                            selectedCategory = cat.value
                                        }
                                    } label: {
                                        Text(cat.label)
                                            .font(.subheadline.weight(.semibold))
                                            .padding(.horizontal, 14)
                                            .padding(.vertical, 7)
                                            .background(
                                                Capsule().fill(
                                                    selectedCategory == cat.value
                                                        ? Color.blue
                                                        : Color.white.opacity(0.1)
                                                )
                                            )
                                            .foregroundColor(
                                                selectedCategory == cat.value ? .white : .secondary
                                            )
                                    }
                                }
                            }
                            .padding(.horizontal, 16)
                        }

                        if filteredBooks.isEmpty {
                            VStack(spacing: 12) {
                                Image(systemName: "book.fill")
                                    .font(.system(size: 40))
                                    .foregroundColor(.secondary)
                                Text("No books in this category")
                                    .font(.subheadline)
                                    .foregroundColor(.secondary)
                            }
                            .frame(maxWidth: .infinity, minHeight: 200)
                        } else {
                            LazyVGrid(columns: columns, spacing: 14) {
                                ForEach(filteredBooks) { book in
                                    NavigationLink {
                                        BookDetailView(book: book)
                                    } label: {
                                        BookCard(book: book)
                                    }
                                    .buttonStyle(.plain)
                                    .contextMenu {
                                        Button {
                                            addToPlaylistBookId = book.id
                                            showAddToPlaylist = true
                                        } label: {
                                            Label("Add to Playlist", systemImage: "text.badge.plus")
                                        }
                                    }
                                }
                            }
                            .padding(.horizontal, 16)
                        }
                    }
                    .padding(.vertical, 8)
                }
            }
        }
        .task { await load() }
        .addToPlaylistPresentation(isPresented: $showAddToPlaylist, mediaType: "book", mediaId: addToPlaylistBookId)
    }

    private func load() async {
        isLoading = true
        error = nil
        do {
            allBooks = try await contentAPI.fetchBooks()
        } catch {
            self.error = error.localizedDescription
        }
        isLoading = false
    }
}

// MARK: - Book Card
struct BookCard: View {
    let book: GOBook

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Cover image — 2:3 aspect ratio for book covers
            Group {
                if let urlStr = book.coverImageUrl, let url = URL(string: urlStr) {
                    CachedAsyncImage(url: url) {
                        Color.white.opacity(0.08)
                            .overlay(
                                Image(systemName: "book.fill")
                                    .font(.system(size: 30))
                                    .foregroundColor(.secondary)
                            )
                    }
                } else {
                    Color.white.opacity(0.08)
                        .overlay(
                            Image(systemName: "book.fill")
                                .font(.system(size: 30))
                                .foregroundColor(.secondary)
                        )
                }
            }
            .aspectRatio(2.0/3.0, contentMode: .fit)
            .clipped()
            .cornerRadius(8)
            .shadow(color: .black.opacity(0.5), radius: 4, x: 0, y: 2)

            VStack(alignment: .leading, spacing: 2) {
                Text(book.title)
                    .font(.caption.bold())
                    .foregroundColor(.white)
                    .lineLimit(2)
                Text(book.author)
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }
        }
    }
}

#endif
