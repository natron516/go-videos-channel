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

// App background modifier
extension View {
    func appBackground() -> some View {
        self.background {
            ZStack {
                Color.black.ignoresSafeArea()
                Image("AppBackground")
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .ignoresSafeArea()
                    .opacity(0.35)
            }
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
        self.buttonStyle(.card)
        #else
        self.buttonStyle(MediaCardButtonStyle())
        #endif
    }
}
