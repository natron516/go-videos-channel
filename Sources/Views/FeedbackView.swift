import SwiftUI
import FirebaseFirestore
import FirebaseAuth

struct FeedbackView: View {
    @Environment(\.dismiss) var dismiss
    @State private var text = ""
    @State private var submitted = false
    @State private var submitting = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()
                Color.clear.appBackground()

                if submitted {
                    VStack(spacing: 20) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 64))
                            .foregroundColor(.green)
                        Text("Thanks for the feedback!")
                            .font(.title2.bold())
                            .foregroundColor(.white)
                        Text("We read every suggestion.")
                            .foregroundColor(.secondary)
                        Button("Done") { dismiss() }
                            .buttonStyle(.borderedProminent)
                            .padding(.top, 8)
                    }
                    .padding()
                } else {
                    VStack(alignment: .leading, spacing: 16) {
                        Text("Have a suggestion or idea for the app?")
                            .font(.headline)
                            .foregroundColor(.white)
                        Text("We'd love to hear it.")
                            .foregroundColor(.secondary)

                        #if os(tvOS)
                        TextField("Type your suggestion…", text: $text, axis: .vertical)
                            .lineLimit(6, reservesSpace: true)
                            .padding(12)
                            .background(Color.white.opacity(0.08))
                            .cornerRadius(10)
                        #else
                        TextEditor(text: $text)
                            .frame(minHeight: 140)
                            .padding(8)
                            .background(Color.white.opacity(0.08))
                            .cornerRadius(10)
                            .foregroundColor(.white)
                            .scrollContentBackground(.hidden)
                        #endif

                        if let err = errorMessage {
                            Text(err)
                                .foregroundColor(.red)
                                .font(.caption)
                        }

                        Button {
                            submit()
                        } label: {
                            Group {
                                if submitting {
                                    ProgressView().tint(.white)
                                } else {
                                    Text("Submit Feedback")
                                }
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 4)
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || submitting)
                    }
                    .padding(24)
                }
            }
            .navigationTitle("App Feedback")
            #if !os(tvOS)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .foregroundColor(.white)
                }
            }
            #endif
        }
    }

    func submit() {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        submitting = true
        errorMessage = nil

        let platform: String
        #if os(tvOS)
        platform = "tvOS"
        #else
        platform = UIDevice.current.userInterfaceIdiom == .pad ? "iPadOS" : "iOS"
        #endif

        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "unknown"

        let user = Auth.auth().currentUser
        // Try top-level fields first, then dig into providerData
        let email = user?.email
            ?? user?.providerData.first?.email
        let name = user?.displayName
            ?? user?.providerData.first?.displayName

        var data: [String: Any] = [
            "text": trimmed,
            "timestamp": FieldValue.serverTimestamp(),
            "platform": platform,
            "appVersion": version,
            "read": false
        ]
        if let uid = user?.uid { data["uid"] = uid }
        if let email = email, !email.isEmpty { data["email"] = email }
        if let name = name, !name.isEmpty { data["name"] = name }

        Firestore.firestore().collection("feedback").addDocument(data: data) { error in
            DispatchQueue.main.async {
                submitting = false
                if let error = error {
                    errorMessage = "Couldn't send — try again. (\(error.localizedDescription))"
                } else {
                    submitted = true
                }
            }
        }
    }
}
