import SwiftUI

struct AboutView: View {
    @State private var showLinkTV = false
    @State private var showDeleteConfirm = false
    @State private var showDeleteError = false
    @State private var showFeedback = false

    var body: some View {
        VStack(spacing: 32) {
            Image(systemName: "cross.circle.fill")
                .font(.system(size: 100))
                .foregroundColor(.accentColor)

            Text("Gospel Outreach of Olympia")
                .font(.largeTitle.bold())

            Text("Watch live services and browse our sermon library.")
                .font(.title3)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)

            Divider()

            VStack(spacing: 8) {
                Text("gospeloutreacholympia.com")
                    .font(.callout)
                    .foregroundColor(.secondary)
            }

            Divider()

            Button {
                showFeedback = true
            } label: {
                Label("Send App Feedback", systemImage: "lightbulb")
            }
            .buttonStyle(.bordered)
            .sheet(isPresented: $showFeedback) { FeedbackView() }

            Divider()

            #if os(iOS)
            Button {
                showLinkTV = true
            } label: {
                Label("Link Apple TV", systemImage: "appletv")
            }
            .buttonStyle(.bordered)
            .sheet(isPresented: $showLinkTV) {
                LinkTVView()
            }
            #endif

            Button(role: .destructive) {
                AuthService.shared.signOut()
            } label: {
                Label("Sign Out", systemImage: "rectangle.portrait.and.arrow.right")
                    .foregroundColor(.red)
            }
            .buttonStyle(.bordered)

            Button(role: .destructive) {
                showDeleteConfirm = true
            } label: {
                Label("Delete Account", systemImage: "trash")
                    .foregroundColor(.red)
            }
            .buttonStyle(.bordered)
        }
        .padding(60)
        .navigationTitle("About")
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
            Text(AuthService.shared.deleteError ?? "Unknown error")
        }
    }
}
