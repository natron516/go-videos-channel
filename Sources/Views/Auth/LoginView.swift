#if os(iOS)
import SwiftUI
import GoogleSignIn
import AuthenticationServices

struct LoginView: View {
    @State private var errorMessage = ""
    @State private var isLoading = false

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            Color.clear.appBackground()

            VStack(spacing: 0) {
                Spacer()

                // Logo
                ZStack {
                    RoundedRectangle(cornerRadius: 20)
                        .fill(LinearGradient(colors: [.red, Color(red: 0.7, green: 0.1, blue: 0.1)], startPoint: .topLeading, endPoint: .bottomTrailing))
                        .frame(width: 80, height: 80)
                    Text("📺").font(.system(size: 36))
                }
                .padding(.bottom, 20)

                Text("GO Media").font(.system(size: 28, weight: .bold)).foregroundColor(.white)
                Text("Sign in to continue")
                    .font(.subheadline).foregroundColor(.white.opacity(0.5))
                    .padding(.bottom, 48)

                VStack(spacing: 14) {
                    if !errorMessage.isEmpty {
                        Text(errorMessage)
                            .font(.caption)
                            .foregroundColor(.red)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal)
                    }

                    // Sign in with Apple
                    SignInWithAppleButton(.signIn) { request in
                        let hashedNonce = AuthService.shared.prepareAppleNonce()
                        request.requestedScopes = [.fullName, .email]
                        request.nonce = hashedNonce
                    } onCompletion: { result in
                        Task {
                            do {
                                try await AuthService.shared.handleAppleSignIn(result: result)
                            } catch {
                                if (error as NSError).code != ASAuthorizationError.canceled.rawValue {
                                    errorMessage = error.localizedDescription
                                }
                            }
                        }
                    }
                    .signInWithAppleButtonStyle(.white)
                    .frame(height: 52)
                    .cornerRadius(12)
                    .padding(.horizontal, 40)

                    // Sign in with Google
                    Button(action: handleGoogle) {
                        HStack(spacing: 12) {
                            ZStack {
                                Circle().fill(Color.white).frame(width: 22, height: 22)
                                Text("G").font(.system(size: 14, weight: .bold)).foregroundColor(Color(red: 0.26, green: 0.52, blue: 0.96))
                            }
                            if isLoading {
                                ProgressView().tint(.black)
                            } else {
                                Text("Sign in with Google")
                                    .font(.system(size: 17, weight: .semibold))
                                    .foregroundColor(.black)
                            }
                        }
                        .frame(maxWidth: .infinity)
                        .frame(height: 52)
                        .background(Color.white)
                        .cornerRadius(12)
                    }
                    .disabled(isLoading)
                    .padding(.horizontal, 40)
                }

                Spacer()
            }
        }
    }

    func handleGoogle() {
        guard let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
              let root = scene.windows.first?.rootViewController else { return }
        isLoading = true
        Task {
            do {
                try await AuthService.shared.signInWithGoogle(presenting: root)
            } catch {
                errorMessage = error.localizedDescription
            }
            isLoading = false
        }
    }
}
#endif
