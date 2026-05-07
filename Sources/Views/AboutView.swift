import SwiftUI

struct AboutView: View {
    @State private var showLinkTV = false

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
        }
        .padding(60)
        .navigationTitle("About")
    }
}
