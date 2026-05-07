#if os(iOS)
import SwiftUI
import FirebaseFirestore
import FirebaseAuth

struct LinkTVView: View {
    @Environment(\.dismiss) var dismiss
    @State private var code = ""
    @State private var status: LinkStatus = .idle
    @FocusState private var focused: Bool

    enum LinkStatus {
        case idle, linking, success, error(String)
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()

                VStack(spacing: 32) {
                    Image(systemName: "appletv.fill")
                        .font(.system(size: 60))
                        .foregroundColor(.white)

                    VStack(spacing: 8) {
                        Text("Link Your Apple TV")
                            .font(.title2.bold())
                            .foregroundColor(.white)
                        Text("Enter the 6-character code shown on your TV")
                            .font(.subheadline)
                            .foregroundColor(.white.opacity(0.5))
                            .multilineTextAlignment(.center)
                    }

                    TextField("", text: $code)
                        .font(.system(size: 32, weight: .bold, design: .monospaced))
                        .multilineTextAlignment(.center)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.characters)
                        .foregroundColor(.white)
                        .frame(height: 60)
                        .background(Color.white.opacity(0.08))
                        .cornerRadius(12)
                        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.white.opacity(0.15), lineWidth: 1))
                        .padding(.horizontal, 40)
                        .focused($focused)
                        .onChange(of: code) { new in
                            code = String(new.prefix(6)).uppercased()
                        }

                    switch status {
                    case .idle:
                        Button(action: linkTV) {
                            Text("Link TV")
                                .font(.system(size: 17, weight: .semibold))
                                .foregroundColor(.white)
                                .frame(maxWidth: .infinity)
                                .frame(height: 52)
                                .background(code.count == 6 ? Color.red : Color.gray.opacity(0.3))
                                .cornerRadius(12)
                        }
                        .disabled(code.count < 6)
                        .padding(.horizontal, 40)
                    case .linking:
                        ProgressView().tint(.white)
                    case .success:
                        Label("TV Linked!", systemImage: "checkmark.circle.fill")
                            .foregroundColor(.green)
                            .font(.title3.bold())
                    case .error(let msg):
                        VStack(spacing: 12) {
                            Text(msg).font(.caption).foregroundColor(.red).multilineTextAlignment(.center)
                            Button("Try Again") { status = .idle; code = "" }
                                .foregroundColor(.white)
                        }
                    }

                    Spacer()
                }
                .padding(.top, 40)
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }.foregroundColor(.white)
                }
            }
        }
        .onAppear { focused = true }
    }

    func linkTV() {
        guard let uid = Auth.auth().currentUser?.uid else {
            status = .error("You must be signed in to link a TV.")
            return
        }
        status = .linking
        let db = Firestore.firestore()
        let ref = db.collection("tvSessions").document(code)

        Task {
            do {
                // Verify session exists
                let snap = try await ref.getDocument()
                guard snap.exists else {
                    status = .error("Code not found. Make sure your TV is showing the code and try again.")
                    return
                }
                // Write uid — Cloud Function mints the custom token
                try await ref.setData(["uid": uid, "status": "pending_token"], merge: true)
                status = .success
                // Auto-dismiss after success
                try? await Task.sleep(nanoseconds: 1_500_000_000)
                dismiss()
            } catch {
                status = .error(error.localizedDescription)
            }
        }
    }
}
#endif
