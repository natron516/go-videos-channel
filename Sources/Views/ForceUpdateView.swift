import SwiftUI

// MARK: - Full-screen blocking update wall

struct ForceUpdateView: View {
    @ObservedObject private var forceUpdate = ForceUpdateService.shared

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            VStack(spacing: 24) {
                Image(systemName: "arrow.down.circle.fill")
                    .font(.system(size: 72))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [.blue, .purple],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )

                Text("Update Required")
                    .font(.title)
                    .fontWeight(.bold)
                    .foregroundColor(.white)

                Text(forceUpdate.updateMessage.isEmpty
                     ? "A new version of GO Media is available. Please update to continue."
                     : forceUpdate.updateMessage)
                    .font(.body)
                    .foregroundColor(.gray)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 40)

                #if os(tvOS)
                Text("Please update from the App Store on your Apple TV.")
                    .font(.callout)
                    .foregroundColor(.secondary)
                    .padding(.top, 8)
                #else
                Button(action: openAppStore) {
                    HStack(spacing: 8) {
                        Image(systemName: "arrow.down.app.fill")
                        Text("Update Now")
                            .fontWeight(.semibold)
                    }
                    .padding(.horizontal, 32)
                    .padding(.vertical, 14)
                    .background(
                        LinearGradient(
                            colors: [.blue, .purple],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .foregroundColor(.white)
                    .clipShape(Capsule())
                }
                .padding(.top, 8)
                #endif
            }
        }
    }

    #if !os(tvOS)
    private func openAppStore() {
        if let url = URL(string: "itms-apps://apps.apple.com/app/id6744253498") {
            UIApplication.shared.open(url)
        }
    }
    #endif
}

// MARK: - Dismissable soft update banner

struct UpdateRecommendedBanner: View {
    @ObservedObject private var forceUpdate = ForceUpdateService.shared
    @State private var dismissed = false

    var body: some View {
        if forceUpdate.updateRecommended && !dismissed {
            HStack(spacing: 12) {
                Image(systemName: "arrow.down.circle.fill")
                    .foregroundColor(.blue)

                Text("A new version is available")
                    .font(.subheadline)
                    .foregroundColor(.white)

                Spacer()

                #if os(tvOS)
                Button("OK") { dismissed = true }
                    .font(.subheadline.weight(.semibold))
                #else
                Button(action: {
                    if let url = URL(string: "itms-apps://apps.apple.com/app/id6744253498") {
                        UIApplication.shared.open(url)
                    }
                }) {
                    Text("Update")
                        .font(.subheadline.weight(.semibold))
                        .foregroundColor(.blue)
                }

                Button(action: { dismissed = true }) {
                    Image(systemName: "xmark")
                        .font(.caption.weight(.bold))
                        .foregroundColor(.gray)
                }
                #endif
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(Color.white.opacity(0.12))
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .transition(.move(edge: .top).combined(with: .opacity))
        }
    }
}
