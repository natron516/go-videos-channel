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

    private var authListener: AuthStateDidChangeListenerHandle?

    init() {
        authListener = Auth.auth().addStateDidChangeListener { [weak self] _, user in
            self?.user = user
            self?.isLoading = false
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
