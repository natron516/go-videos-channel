import SwiftUI

struct LiveStreamView: View {
    @EnvironmentObject var api: MuxAPI
    @State private var liveStream: MuxLiveStream?
    @State private var isLoading = true
    @State private var error: String?

    let refreshInterval: TimeInterval = 30

    var body: some View {
        Group {
            if isLoading {
                ProgressView("Checking live status…")
            } else if let stream = liveStream, let url = stream.streamURL {
                VideoPlayerView(url: url)
                    .ignoresSafeArea()
            } else {
                VStack(spacing: 24) {
                    Image(systemName: "video.slash")
                        .font(.system(size: 80))
                        .foregroundColor(.secondary)
                    Text("No Live Service Right Now")
                        .font(.title)
                    Text("Check back on Sundays for our live service.")
                        .foregroundColor(.secondary)
                    Button("Refresh") { Task { await load() } }
                        .buttonStyle(.borderedProminent)
                }
            }
        }
        .navigationTitle("Live")
        .task { await load() }
        .onAppear { startPolling() }
    }

    func load() async {
        isLoading = true
        error = nil
        do {
            liveStream = try await api.activeLiveStream()
        } catch {
            self.error = error.localizedDescription
        }
        isLoading = false
    }

    func startPolling() {
        Timer.scheduledTimer(withTimeInterval: refreshInterval, repeats: true) { _ in
            Task { await load() }
        }
    }
}
