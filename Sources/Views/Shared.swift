import SwiftUI

// Toggle pill dimensions per platform
private var pillWidth: CGFloat {
    #if os(tvOS)
    return 72
    #else
    return 44
    #endif
}
private var pillHeight: CGFloat {
    #if os(tvOS)
    return 40
    #else
    return 26
    #endif
}
private var thumbSize: CGFloat {
    #if os(tvOS)
    return 32
    #else
    return 20
    #endif
}

// Shared pill visual
private struct TogglePill: View {
    let isOn: Bool
    let color: Color

    var body: some View {
        ZStack(alignment: isOn ? .trailing : .leading) {
            Capsule()
                .fill(isOn ? color : Color.gray.opacity(0.45))
                .frame(width: pillWidth, height: pillHeight)
            Circle()
                .fill(Color.white)
                .frame(width: thumbSize, height: thumbSize)
                .padding(3)
                .shadow(color: .black.opacity(0.2), radius: 2, x: 0, y: 1)
        }
        .frame(width: pillWidth, height: pillHeight)
    }
}

// Focusable autoplay toggle
struct AutoplayToggleButton: View {
    @Binding var enabled: Bool

    var body: some View {
        Button {
            enabled.toggle()
        } label: {
            HStack(spacing: 6) {
                TogglePill(isOn: enabled, color: .blue)
                Text("AutoRun")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                    .fixedSize()
            }
        }
        .buttonStyle(CapsuleFocusButtonStyle())
        .animation(.easeInOut(duration: 0.2), value: enabled)
    }
}

// Focusable shuffle toggle button
struct ShuffleToggleButton: View {
    @Binding var enabled: Bool

    var body: some View {
        Button {
            enabled.toggle()
        } label: {
            HStack(spacing: 6) {
                TogglePill(isOn: enabled, color: .green)
                Text("Shuffle")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                    .fixedSize()
            }
        }
        .buttonStyle(CapsuleFocusButtonStyle())
        .animation(.easeInOut(duration: 0.2), value: enabled)
    }
}

// ButtonStyle that replaces the default tvOS focus box with a rounded border around the full content
private struct CapsuleFocusButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        CapsuleFocusLabel(label: configuration.label)
    }

    struct CapsuleFocusLabel: View {
        let label: ButtonStyle.Configuration.Label
        @Environment(\.isFocused) var isFocused

        var body: some View {
            label
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .overlay(
                    RoundedRectangle(cornerRadius: 24)
                        .stroke(Color.white.opacity(isFocused ? 1 : 0), lineWidth: 3)
                )
                .scaleEffect(isFocused ? 1.05 : 1.0)
                .animation(.easeInOut(duration: 0.15), value: isFocused)
        }
    }
}

// Platform-appropriate modal presentation
extension View {
    func addToPlaylistPresentation(isPresented: Binding<Bool>, assetId: String?) -> some View {
        #if os(tvOS)
        return self.fullScreenCover(isPresented: isPresented) {
            if let id = assetId {
                AddToPlaylistView(assetId: id)
            }
        }
        #else
        return self.sheet(isPresented: isPresented) {
            if let id = assetId {
                AddToPlaylistView(assetId: id)
            }
        }
        #endif
    }

    /// Generic playlist presentation for any media type (book, article, audio, video)
    func addToPlaylistPresentation(isPresented: Binding<Bool>, mediaType: String, mediaId: String?) -> some View {
        #if os(tvOS)
        return self.fullScreenCover(isPresented: isPresented) {
            if let id = mediaId {
                AddToPlaylistView(mediaType: mediaType, mediaId: id)
            }
        }
        #else
        return self.sheet(isPresented: isPresented) {
            if let id = mediaId {
                AddToPlaylistView(mediaType: mediaType, mediaId: id)
            }
        }
        #endif
    }
}

// Search toolbar modifier for iOS
extension View {
    func searchToolbar() -> some View {
        #if os(tvOS)
        return self
        #else
        return self.modifier(SearchToolbarModifier())
        #endif
    }
}

#if !os(tvOS)
private struct SearchToolbarModifier: ViewModifier {
    @State private var showSearch = false

    func body(content: Content) -> some View {
        content
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button { showSearch = true } label: {
                        Image(systemName: "magnifyingglass")
                    }
                }
            }
            .sheet(isPresented: $showSearch) {
                NavigationStack { SearchView() }
            }
    }
}
#endif

#if !os(tvOS)
/// Applies the consistent GO Videos nav bar: logo left, 5 icons right.
/// Each view owns its own @State for the sheets it presents.
struct GONavBarModifier: ViewModifier {
    @Binding var showLinkTV: Bool
    @Binding var showWatchTimer: Bool
    @Binding var showSearch: Bool
    @ObservedObject var autoplay: AutoplayManager
    @State private var showDeleteConfirm = false
    @State private var showDeleteError = false
    @State private var showFeedback = false
    @ObservedObject private var watchTimer = WatchTimerManager.shared
    @ObservedObject private var auth = AuthService.shared

    func body(content: Content) -> some View {
        content
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.hidden, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Image("CrossLogo")
                        .resizable()
                        .scaledToFit()
                        .frame(height: UIDevice.current.userInterfaceIdiom == .pad ? 36 : 28)
                }
                ToolbarItemGroup(placement: .navigationBarTrailing) {
                    Button { autoplay.enabled.toggle() } label: {
                        Image(systemName: autoplay.enabled ? "forward.end.fill" : "forward.end")
                            .foregroundColor(autoplay.enabled ? .blue : .secondary)
                    }
                    Button { autoplay.shuffle.toggle() } label: {
                        Image(systemName: "shuffle")
                            .foregroundColor(autoplay.shuffle ? .green : .secondary)
                    }
                    Button { showSearch = true } label: {
                        Image(systemName: "magnifyingglass")
                    }
                    Menu {
                        Button { showWatchTimer = true } label: {
                            Label(
                                watchTimer.isRunning ? "Watch Timer (ON)" : "Watch Timer",
                                systemImage: "timer"
                            )
                        }
                        Button { showLinkTV = true } label: {
                            Label("Link Apple TV", systemImage: "appletv")
                        }
                        Button { showFeedback = true } label: {
                            Label("Send Feedback", systemImage: "lightbulb")
                        }
                        Divider()
                        Button(role: .destructive) {
                            AuthService.shared.signOut()
                        } label: {
                            Label("Sign Out", systemImage: "rectangle.portrait.and.arrow.right")
                        }
                        Button(role: .destructive) {
                            showDeleteConfirm = true
                        } label: {
                            Label("Delete Account", systemImage: "trash")
                        }
                    } label: {
                        Image(systemName: "person.circle.fill")
                    }
                }
            }
            .alert("Delete Account", isPresented: $showDeleteConfirm) {
                Button("Cancel", role: .cancel) { }
                Button("Delete", role: .destructive) {
                    Task {
                        await AuthService.shared.deleteAccount()
                        if AuthService.shared.deleteError != nil {
                            showDeleteError = true
                        }
                    }
                }
            } message: {
                Text("Are you sure? This will permanently delete your account and all associated data. This action cannot be undone.")
            }
            .alert("Error", isPresented: $showDeleteError) {
                Button("OK") { AuthService.shared.deleteError = nil }
            } message: {
                Text(auth.deleteError ?? "Unknown error")
            }
            .sheet(isPresented: $showFeedback) { FeedbackView() }
    }
}

struct WatchTimerToolbarButton: View {
    let action: () -> Void
    @ObservedObject private var watchTimer = WatchTimerManager.shared
    var body: some View {
        Button(action: action) {
            Image(systemName: "timer")
                .foregroundColor(watchTimer.isRunning ? .orange : .secondary)
        }
    }
}

extension View {
    func goNavBar(
        showLinkTV: Binding<Bool>,
        showWatchTimer: Binding<Bool>,
        showSearch: Binding<Bool>,
        autoplay: AutoplayManager = .shared
    ) -> some View {
        self.modifier(GONavBarModifier(
            showLinkTV: showLinkTV,
            showWatchTimer: showWatchTimer,
            showSearch: showSearch,
            autoplay: autoplay
        ))
    }
}
#endif

#if os(tvOS)
/// tvOS toolbar: autoplay, shuffle, timer toggles in the top-right of the detail view.
struct TVToolbarModifier: ViewModifier {
    @ObservedObject var autoplay: AutoplayManager
    @Binding var showWatchTimer: Bool

    func body(content: Content) -> some View {
        content
            .toolbar {
                ToolbarItemGroup(placement: .automatic) {
                    // Autoplay
                    Button { autoplay.enabled.toggle() } label: {
                        Image(systemName: autoplay.enabled ? "forward.end.fill" : "forward.end")
                            .foregroundColor(autoplay.enabled ? .blue : .primary)
                    }
                    // Shuffle
                    Button { autoplay.shuffle.toggle() } label: {
                        Image(systemName: "shuffle")
                            .foregroundColor(autoplay.shuffle ? .green : .primary)
                    }
                    // Watch Timer
                    TVWatchTimerButton { showWatchTimer = true }
                }
            }
    }
}

struct TVWatchTimerButton: View {
    let action: () -> Void
    @ObservedObject private var watchTimer = WatchTimerManager.shared
    var body: some View {
        Button(action: action) {
            Image(systemName: "timer")
                .foregroundColor(watchTimer.isRunning ? .orange : .primary)
        }
    }
}

extension View {
    func tvToolbar(showWatchTimer: Binding<Bool>, autoplay: AutoplayManager = .shared) -> some View {
        self.modifier(TVToolbarModifier(autoplay: autoplay, showWatchTimer: showWatchTimer))
    }
}
#endif

// App background modifier
extension View {
    func appBackground() -> some View {
        self.background {
            LinearGradient(
                colors: [
                    Color(red: 0.08, green: 0.08, blue: 0.10),
                    Color(red: 0.15, green: 0.15, blue: 0.18),
                    Color(red: 0.08, green: 0.08, blue: 0.10)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()
        }
    }
}

// Cross-platform media card button style
struct MediaCardButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.96 : 1.0)
            .animation(.easeInOut(duration: 0.12), value: configuration.isPressed)
    }
}

extension View {
    func mediaCardStyle() -> some View {
        #if os(tvOS)
        self.buttonStyle(TVMediaCardButtonStyle())
        #else
        self.buttonStyle(MediaCardButtonStyle())
        #endif
    }
}

#if os(tvOS)
struct TVMediaCardButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(configuration.isPressed ? 0.85 : 1.0)
    }
}
#endif
