#if os(iOS)
import SwiftUI
import GoogleSignIn
import AuthenticationServices

struct LoginView: View {
    @State private var errorMessage = ""
    @State private var isLoading = false
    @State private var appeared = false
    @ObservedObject private var auth = AuthService.shared

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            Color.clear.appBackground()

            VStack(spacing: 0) {
                Spacer()

                // Account deleted banner
                if auth.accountDeleted {
                    HStack(spacing: 8) {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(.green)
                        Text("Your account has been successfully deleted.")
                            .font(.subheadline.bold())
                            .foregroundColor(.white)
                    }
                    .padding(14)
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
                    .padding(.horizontal, 40)
                    .padding(.bottom, 24)
                    .onAppear {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 5) {
                            auth.accountDeleted = false
                        }
                    }
                }

                // App Icon
                if let uiImage = UIImage(named: "AppIcon") ?? UIImage(named: "NavLogo") {
                    Image(uiImage: uiImage)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 90, height: 90)
                        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                        .shadow(color: .red.opacity(0.4), radius: 20, y: 8)
                        .padding(.bottom, 20)
                        .scaleEffect(appeared ? 1.0 : 0.8)
                        .opacity(appeared ? 1.0 : 0)
                } else {
                    ZStack {
                        RoundedRectangle(cornerRadius: 22, style: .continuous)
                            .fill(LinearGradient(colors: [.red, Color(red: 0.7, green: 0.1, blue: 0.1)], startPoint: .topLeading, endPoint: .bottomTrailing))
                            .frame(width: 90, height: 90)
                            .shadow(color: .red.opacity(0.4), radius: 20, y: 8)
                        Text("📺").font(.system(size: 40))
                    }
                    .padding(.bottom, 20)
                    .scaleEffect(appeared ? 1.0 : 0.8)
                    .opacity(appeared ? 1.0 : 0)
                }

                Text("GO Media")
                    .font(.system(size: 32, weight: .bold, design: .rounded))
                    .foregroundColor(.white)
                    .opacity(appeared ? 1.0 : 0)
                    .offset(y: appeared ? 0 : 10)

                Text("Sign in to continue")
                    .font(.subheadline)
                    .foregroundColor(.white.opacity(0.45))
                    .padding(.top, 6)
                    .padding(.bottom, 40)
                    .opacity(appeared ? 1.0 : 0)
                    .offset(y: appeared ? 0 : 10)

                // Sign-in card
                VStack(spacing: 16) {
                    if !errorMessage.isEmpty {
                        Text(errorMessage)
                            .font(.caption)
                            .foregroundColor(.red)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal)
                            .transition(.opacity)
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
                    .signInWithAppleButtonStyle(.whiteOutline)
                    .frame(height: 54)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))

                    // Divider
                    HStack {
                        Rectangle().fill(Color.white.opacity(0.15)).frame(height: 1)
                        Text("or").font(.caption).foregroundColor(.white.opacity(0.35))
                        Rectangle().fill(Color.white.opacity(0.15)).frame(height: 1)
                    }

                    // Sign in with Google
                    Button(action: handleGoogle) {
                        HStack(spacing: 10) {
                            // Google "G" logo
                            ZStack {
                                Circle().fill(Color.white).frame(width: 24, height: 24)
                                Text("G")
                                    .font(.system(size: 15, weight: .bold))
                                    .foregroundColor(Color(red: 0.26, green: 0.52, blue: 0.96))
                            }
                            if isLoading {
                                ProgressView().tint(.white)
                            } else {
                                Text("Sign in with Google")
                                    .font(.system(size: 17, weight: .semibold))
                                    .foregroundColor(.white)
                            }
                        }
                        .frame(maxWidth: .infinity)
                        .frame(height: 54)
                        .background(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .fill(Color.white.opacity(0.12))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .stroke(Color.white.opacity(0.2), lineWidth: 1)
                        )
                    }
                    .disabled(isLoading)
                }
                .padding(.horizontal, 32)
                .padding(.vertical, 28)
                .frame(maxWidth: 400)
                .background(
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .fill(.ultraThinMaterial)
                        .shadow(color: .black.opacity(0.3), radius: 30, y: 10)
                )
                .padding(.horizontal, 28)
                .opacity(appeared ? 1.0 : 0)
                .offset(y: appeared ? 0 : 20)

                Spacer()
                Spacer()
            }
        }
        .onAppear {
            withAnimation(.easeOut(duration: 0.6).delay(0.2)) {
                appeared = true
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
