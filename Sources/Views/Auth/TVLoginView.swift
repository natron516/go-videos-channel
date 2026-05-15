#if os(tvOS)
import SwiftUI

struct TVLoginView: View {
    @StateObject private var auth = AuthService.shared
    @State private var sessionCode: String = ""
    @State private var statusMessage = "Waiting for sign-in…"
    @State private var isError = false
    @State private var isGenerating = true
    @State private var pollTask: Task<Void, Never>?

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            Color.clear.appBackground()

            VStack(spacing: 32) {
                if auth.accountDeleted {
                    HStack(spacing: 12) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.title2)
                            .foregroundColor(.green)
                        Text("Your account has been successfully deleted.")
                            .font(.title3.bold())
                            .foregroundColor(.white)
                    }
                    .padding(20)
                    .background(Color.green.opacity(0.15).cornerRadius(12))
                    .onAppear {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 5) {
                            auth.accountDeleted = false
                        }
                    }
                }

                Text("📺").font(.system(size: 48))

                Text("Sign In to\nGO Media")
                    .font(.system(size: 40, weight: .bold))
                    .foregroundColor(.white)
                    .multilineTextAlignment(.center)

                VStack(alignment: .leading, spacing: 12) {
                    StepRow(number: "1", text: "Open GO Media on your iPhone")
                    HStack(spacing: 14) {
                        ZStack {
                            Circle().fill(Color.red).frame(width: 32, height: 32)
                            Text("2").font(.system(size: 15, weight: .bold)).foregroundColor(.white)
                        }
                        (Text("Tap the Profile icon ") + Text(Image(systemName: "person.circle.fill")) + Text(" → Link Apple TV"))
                            .font(.callout)
                            .foregroundColor(.white.opacity(0.8))
                    }
                    StepRow(number: "3", text: "Enter the code below")
                }

                if !sessionCode.isEmpty {
                    Text(sessionCode)
                        .font(.system(size: 36, weight: .bold, design: .monospaced))
                        .foregroundColor(.white)
                        .tracking(8)
                        .padding(.top, 8)
                }

                Text(statusMessage)
                    .font(.callout)
                    .foregroundColor(isError ? .red : .white.opacity(0.5))

                if isError {
                    Button("Try Again") { regenerate() }
                        .buttonStyle(.borderedProminent)
                        .tint(.red)
                }
            }
            .frame(maxWidth: 560)
            .padding(60)
        }
        .onAppear { regenerate() }
        .onDisappear { pollTask?.cancel() }
    }

    func regenerate() {
        pollTask?.cancel()
        isGenerating = true
        isError = false
        statusMessage = "Generating sign-in code…"
        sessionCode = ""

        Task {
            do {
                let code = try await auth.createTVSession()
                sessionCode = code
                statusMessage = "Enter this code on your iPhone"
                isGenerating = false
                startPolling(code: code)
            } catch {
                isError = true
                statusMessage = "Failed to generate code. Check your connection."
                isGenerating = false
            }
        }
    }

    func startPolling(code: String) {
        pollTask = Task {
            do {
                statusMessage = "Waiting for sign-in…"
                let token = try await auth.waitForTVToken(sessionCode: code)
                guard !Task.isCancelled else { return }
                statusMessage = "Signing in…"
                try await auth.signInWithCustomToken(token)
            } catch {
                guard !Task.isCancelled else { return }
                isError = true
                statusMessage = error.localizedDescription
            }
        }
    }


}

struct StepRow: View {
    let number: String
    let text: String
    var body: some View {
        HStack(spacing: 14) {
            ZStack {
                Circle().fill(Color.red).frame(width: 32, height: 32)
                Text(number).font(.system(size: 15, weight: .bold)).foregroundColor(.white)
            }
            Text(text).font(.callout).foregroundColor(.white.opacity(0.8))
        }
    }
}
#endif
