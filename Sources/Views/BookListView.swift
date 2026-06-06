import SwiftUI

#if !os(tvOS)

struct BookListView: View {
    var searchText: String = ""
    @ObservedObject private var contentAPI = ContentAPI.shared
    @State private var allBooks: [GOBook] = []
    @State private var isLoading = true
    @State private var error: String?
    @State private var selectedCategories: Set<String> = []
    @State private var showAddToPlaylist = false
    @State private var addToPlaylistBookId: String?

    private let categories: [(value: String, label: String)] = [
        ("books-for-boys", "Books for Boys"),
        ("books-for-girls", "Books for Girls"),
        ("theology", "Theology"),
        ("books-for-mothers", "Books for Mothers"),
    ]

    private var filteredBooks: [GOBook] {
        var books = selectedCategories.isEmpty ? allBooks : allBooks.filter { selectedCategories.contains($0.category) }
        if !searchText.isEmpty {
            let q = searchText.lowercased()
            books = books.filter { $0.title.lowercased().contains(q) || $0.author.lowercased().contains(q) }
        }
        return books
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
            } else if !isLoading && allBooks.isEmpty {
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
                        // Category pill bar (multiselect — empty = All)
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 8) {
                                ForEach(categories, id: \.value) { cat in
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
        .overlay {
            if isLoading {
                ProgressView("Loading…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color.black.opacity(0.3))
            }
        }
        .task { await load() }
        .addToPlaylistPresentation(isPresented: $showAddToPlaylist, mediaType: "book", mediaId: addToPlaylistBookId)
    }

    private func load() async {
        // Use preloaded cache if available
        if let cached = ContentPreloader.shared.books {
            allBooks = cached
            isLoading = false
            return
        }
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
