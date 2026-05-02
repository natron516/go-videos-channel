import SwiftUI

struct SearchView: View {
    @EnvironmentObject var api: MuxAPI
    @State private var allAssets: [MuxAsset] = []
    @State private var query = ""

    var results: [MuxAsset] {
        guard !query.isEmpty else { return [] }
        let q = query.lowercased()
        return allAssets.filter {
            $0.title.lowercased().contains(q) ||
            ($0.speaker?.lowercased().contains(q) ?? false) ||
            ($0.category?.lowercased().contains(q) ?? false)
        }
    }

    var columns: [GridItem] {
        #if os(tvOS)
        return Array(repeating: GridItem(.flexible(), spacing: 40), count: 4)
        #else
        return [GridItem(.adaptive(minimum: 280))]
        #endif
    }

    var body: some View {
        VStack(spacing: 0) {
            // Search field
            HStack {
                Image(systemName: "magnifyingglass").foregroundColor(.secondary)
                TextField("Search videos, speakers…", text: $query)
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
            .padding(.horizontal, 40)
            .padding(.vertical, 20)

            // Results
            ScrollView {
                if query.isEmpty {
                    VStack(spacing: 16) {
                        Image(systemName: "magnifyingglass")
                            .font(.system(size: 60))
                            .foregroundColor(.secondary)
                        Text("Type to search all videos")
                            .font(.title2).foregroundColor(.secondary)
                    }
                    .padding(.top, 60)
                } else if results.isEmpty {
                    Text("No results for \"\(query)\"")
                        .font(.title2).foregroundColor(.secondary)
                        .padding(.top, 60)
                } else {
                    LazyVGrid(columns: columns, spacing: 40) {
                        ForEach(results) { asset in
                            Button {
                                if let url = asset.streamURL { presentPlayer(url: url) }
                            } label: {
                                SermonCardView(asset: asset)
                            }
                            .mediaCardStyle()
                        }
                    }
                    .padding(40)
                }
            }
        }
        .navigationTitle("Search")
        .navigationBarBackButtonHidden(true)
        .task { allAssets = (try? await api.fetchAssets()) ?? [] }
    }
}
