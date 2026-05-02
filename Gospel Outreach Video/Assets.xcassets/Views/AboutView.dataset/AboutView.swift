import SwiftUI

struct AboutView: View {
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
                Text("gospeloutreacholympia.com") // update with real URL
                    .font(.callout)
                    .foregroundColor(.secondary)
            }
        }
        .padding(60)
        .navigationTitle("About")
    }
}
