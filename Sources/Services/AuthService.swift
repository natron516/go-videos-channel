import Foundation
import FirebaseAuth
import FirebaseCore
import FirebaseFirestore
import AuthenticationServices
import CryptoKit

#if os(iOS)
import GoogleSignIn
import GoogleSignInSwift
#endif

@MainActor
class AuthService: ObservableObject {
    static let shared = AuthService()

    @Published var user: User?
    @Published var isLoading = true
    @Published var hasPrivateAccess = false

    private var authListener: AuthStateDidChangeListenerHandle?
    private var blockListener: ListenerRegistration?

    init() {
        authListener = Auth.auth().addStateDidChangeListener { [weak self] _, user in
            let wasNil = self?.user == nil
            self?.user = user
            self?.isLoading = false
            if let user = user {
                // Record first-ever login for new signup notifications
                if wasNil { self?.recordSignupIfNew(user) }
                // Check private content access
                self?.refreshPrivateAccess(uid: user.uid)
                // Listen for block flag — instant kick if admin blocks this user
                self?.listenForBlock(uid: user.uid)
            } else {
                self?.hasPrivateAccess = false
                self?.blockListener?.remove()
                self?.blockListener = nil
            }
        }
    }

    /// Real-time listener on users/{uid} — signs out immediately if blocked.
    private func listenForBlock(uid: String) {
        blockListener?.remove()
        blockListener = Firestore.firestore()
            .collection("users").document(uid)
            .addSnapshotListener { [weak self] snap, _ in
                guard let data = snap?.data(),
                      data["blocked"] as? Bool == true else { return }
                // Force sign-out
                self?.signOut()
            }
    }

    /// Write to newSignups/{uid} if this user hasn't been recorded yet.
    /// The go-admin polling endpoint picks these up for Telegram + email notifications.
    private func recordSignupIfNew(_ user: User) {
        let db = Firestore.firestore()
        let ref = db.collection("newSignups").document(user.uid)
        ref.getDocument { snap, _ in
            guard snap?.exists != true else { return } // Already recorded
            let platform: String
            #if os(tvOS)
            platform = "tvOS"
            #else
            platform = UIDevice.current.userInterfaceIdiom == .pad ? "iPadOS" : "iOS"
            #endif
            ref.setData([
                "uid": user.uid,
                "email": user.email ?? "",
                "displayName": user.displayName ?? "",
                "provider": user.providerData.first?.providerID ?? "unknown",
                "platform": platform,
                "createdAt": ISO8601DateFormatter().string(from: Date()),
                "notified": false,
            ])
        }
    }

    /// Fetch the user's private access flag from Firestore.
    func refreshPrivateAccess(uid: String) {
        let db = Firestore.firestore()
        db.collection("users").document(uid).getDocument { [weak self] snap, _ in
            let access = snap?.data()?["privateAccess"] as? Bool ?? false
            DispatchQueue.main.async { self?.hasPrivateAccess = access }
        }
    }

    var isLoggedIn: Bool { user != nil }

    // MARK: - Sign In with Google (iOS)
    #if os(iOS)
    func signInWithGoogle(presenting viewController: UIViewController) async throws {
        guard let clientID = FirebaseApp.app()?.options.clientID else {
            throw NSError(domain: "Auth", code: -1, userInfo: [NSLocalizedDescriptionKey: "Google Sign In not configured. Enable Google provider in Firebase console and update GoogleService-Info.plist."])
        }
        let config = GIDConfiguration(clientID: clientID)
        GIDSignIn.sharedInstance.configuration = config
        let result = try await GIDSignIn.sharedInstance.signIn(withPresenting: viewController)
        guard let idToken = result.user.idToken?.tokenString else {
            throw NSError(domain: "Auth", code: -1, userInfo: [NSLocalizedDescriptionKey: "Missing Google ID token"])
        }
        let credential = GoogleAuthProvider.credential(
            withIDToken: idToken,
            accessToken: result.user.accessToken.tokenString
        )
        let authResult = try await Auth.auth().signIn(with: credential)
        user = authResult.user
    }
    #endif

    // MARK: - Sign In with Apple
    private var currentNonce: String?

    func handleAppleSignIn(result: Result<ASAuthorization, Error>) async throws {
        switch result {
        case .success(let auth):
            guard let appleCredential = auth.credential as? ASAuthorizationAppleIDCredential,
                  let idTokenData = appleCredential.identityToken,
                  let idToken = String(data: idTokenData, encoding: .utf8),
                  let nonce = currentNonce else {
                throw NSError(domain: "Auth", code: -1, userInfo: [NSLocalizedDescriptionKey: "Apple Sign In failed - missing token"])
            }
            let credential = OAuthProvider.appleCredential(
                withIDToken: idToken,
                rawNonce: nonce,
                fullName: appleCredential.fullName
            )
            let authResult = try await Auth.auth().signIn(with: credential)
            user = authResult.user
        case .failure(let error):
            throw error
        }
    }

    func prepareAppleNonce() -> String {
        let nonce = randomNonceString()
        currentNonce = nonce
        return sha256(nonce)
    }

    private func randomNonceString(length: Int = 32) -> String {
        precondition(length > 0)
        var bytes = [UInt8](repeating: 0, count: length)
        let result = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        guard result == errSecSuccess else { return "" }
        let charset = Array("0123456789ABCDEFGHIJKLMNOPQRSTUVXYZabcdefghijklmnopqrstuvxyz-._")
        return String(bytes.map { charset[Int($0) % charset.count] })
    }

    private func sha256(_ input: String) -> String {
        let data = Data(input.utf8)
        let hash = SHA256.hash(data: data)
        return hash.compactMap { String(format: "%02x", $0) }.joined()
    }

    // MARK: - Email/Password
    func signIn(email: String, password: String) async throws {
        let result = try await Auth.auth().signIn(withEmail: email, password: password)
        user = result.user
    }

    func signUp(email: String, password: String) async throws {
        let result = try await Auth.auth().createUser(withEmail: email, password: password)
        user = result.user
    }

    func signOut() {
        try? Auth.auth().signOut()
        user = nil
    }

    @Published var deleteError: String?
    @Published var accountDeleted = false
    private var appleReauthDelegate: AppleReauthDelegate?

    func deleteAccount() async {
        guard let currentUser = Auth.auth().currentUser else {
            deleteError = "No user signed in."
            return
        }
        do {
            // Try deleting directly first
            let db = Firestore.firestore()
            try? await db.collection("users").document(currentUser.uid).delete()
            try await currentUser.delete()
            accountDeleted = true
            user = nil
        } catch let error as NSError where error.code == AuthErrorCode.requiresRecentLogin.rawValue {
            // Re-authenticate then retry
            do {
                try await reauthenticate()
                try await currentUser.delete()
                accountDeleted = true
                user = nil
            } catch {
                deleteError = "Could not delete account: \(error.localizedDescription)"
            }
        } catch {
            deleteError = "Could not delete account: \(error.localizedDescription)"
        }
    }

    private func reauthenticate() async throws {
        guard let currentUser = Auth.auth().currentUser,
              let providerID = currentUser.providerData.first?.providerID else {
            throw NSError(domain: "Auth", code: -1, userInfo: [NSLocalizedDescriptionKey: "No auth provider found"])
        }

        switch providerID {
        #if os(iOS)
        case "google.com":
            guard let clientID = FirebaseApp.app()?.options.clientID else { throw NSError(domain: "Auth", code: -1) }
            GIDSignIn.sharedInstance.configuration = GIDConfiguration(clientID: clientID)
            // Get the top view controller for presenting
            guard let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
                  let vc = windowScene.windows.first?.rootViewController else {
                throw NSError(domain: "Auth", code: -1, userInfo: [NSLocalizedDescriptionKey: "Cannot present sign-in"])
            }
            let result = try await GIDSignIn.sharedInstance.signIn(withPresenting: vc)
            guard let idToken = result.user.idToken?.tokenString else { throw NSError(domain: "Auth", code: -1) }
            let credential = GoogleAuthProvider.credential(withIDToken: idToken, accessToken: result.user.accessToken.tokenString)
            try await currentUser.reauthenticate(with: credential)
        #endif
        case "apple.com":
            // Trigger a fresh Sign in with Apple to re-authenticate
            let nonce = randomNonceString()
            currentNonce = nonce
            let hashedNonce = sha256(nonce)
            let appleResult = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<ASAuthorization, Error>) in
                let provider = ASAuthorizationAppleIDProvider()
                let request = provider.createRequest()
                request.requestedScopes = [.email]
                request.nonce = hashedNonce
                let delegate = AppleReauthDelegate(continuation: continuation)
                self.appleReauthDelegate = delegate
                let controller = ASAuthorizationController(authorizationRequests: [request])
                controller.delegate = delegate
                controller.performRequests()
            }
            guard let appleCredential = appleResult.credential as? ASAuthorizationAppleIDCredential,
                  let idTokenData = appleCredential.identityToken,
                  let idToken = String(data: idTokenData, encoding: .utf8) else {
                throw NSError(domain: "Auth", code: -1, userInfo: [NSLocalizedDescriptionKey: "Apple re-authentication failed"])
            }
            let credential = OAuthProvider.appleCredential(withIDToken: idToken, rawNonce: nonce, fullName: nil)
            try await currentUser.reauthenticate(with: credential)
        default:
            throw NSError(domain: "Auth", code: -1, userInfo: [NSLocalizedDescriptionKey: "Please sign out, sign back in, then immediately delete your account."])
        }
    }

    // MARK: - TV Session (QR Code flow)
    func createTVSession() async throws -> String {
        let code = String((0..<6).map { _ in "ABCDEFGHJKLMNPQRSTUVWXYZ23456789".randomElement()! })
        let db = Firestore.firestore()
        try await db.collection("tvSessions").document(code).setData([
            "status": "pending",
            "createdAt": FieldValue.serverTimestamp()
        ])
        return code
    }

    func waitForTVToken(sessionCode: String) async throws -> String {
        let db = Firestore.firestore()
        let ref = db.collection("tvSessions").document(sessionCode)
        let deadline = Date().addingTimeInterval(10 * 60)
        while Date() < deadline {
            let snap = try await ref.getDocument()
            if let token = snap.data()?["customToken"] as? String { return token }
            if snap.data()?["status"] as? String == "expired" { throw AuthError.sessionExpired }
            try await Task.sleep(nanoseconds: 3_000_000_000)
        }
        throw AuthError.sessionExpired
    }

    func signInWithCustomToken(_ token: String) async throws {
        let result = try await Auth.auth().signIn(withCustomToken: token)
        user = result.user
    }
}

enum AuthError: LocalizedError {
    case sessionExpired
    var errorDescription: String? {
        switch self { case .sessionExpired: return "Sign-in session expired. Please try again." }
    }
}

/// ASAuthorizationController delegate that bridges to async/await for re-authentication
private class AppleReauthDelegate: NSObject, ASAuthorizationControllerDelegate {
    private var continuation: CheckedContinuation<ASAuthorization, Error>?

    init(continuation: CheckedContinuation<ASAuthorization, Error>) {
        self.continuation = continuation
    }

    func authorizationController(controller: ASAuthorizationController, didCompleteWithAuthorization authorization: ASAuthorization) {
        continuation?.resume(returning: authorization)
        continuation = nil
    }

    func authorizationController(controller: ASAuthorizationController, didCompleteWithError error: Error) {
        continuation?.resume(throwing: error)
        continuation = nil
    }
}
