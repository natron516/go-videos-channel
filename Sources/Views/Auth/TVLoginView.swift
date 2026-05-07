#if os(tvOS)
import SwiftUI
import CoreImage.CIFilterBuiltins

struct TVLoginView: View {
    @StateObject private var auth = AuthService.shared
    @State private var sessionCode: String = ""
    @State private var qrImage: UIImage?
    @State private var statusMessage = "Scan the QR code with your phone to sign in"
    @State private var isError = false
    @State private var isGenerating = true
    @State private var pollTask: Task<Void, Never>?

    var loginURL: String {
        "https://gospel-outreach-tv.web.app/?code=\(sessionCode)"
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            Color.clear.appBackground()

            HStack(spacing: 80) {
                // Left: QR Code
                VStack(spacing: 24) {
                    if let qr = qrImage {
                        Image(uiImage: qr)
                            .interpolation(.none)
                            .resizable()
                            .scaledToFit()
                            .frame(width: 280, height: 280)
                            .clipShape(RoundedRectangle(cornerRadius: 16))
                            .background(Color.white.clipShape(RoundedRectangle(cornerRadius: 16)))
                    } else {
                        RoundedRectangle(cornerRadius: 16)
                            .fill(Color.white.opacity(0.1))
                            .frame(width: 280, height: 280)
                            .overlay(ProgressView().tint(.white))
                    }

                    if !sessionCode.isEmpty {
                        Text(sessionCode)
                            .font(.system(size: 28, weight: .bold, design: .monospaced))
                            .foregroundColor(.white)
                            .tracking(8)
                    }
                }

                // Right: Instructions
                VStack(alignment: .leading, spacing: 20) {
                    Text("📺").font(.system(size: 48))

                    Text("Sign In to\nGO Media")
                        .font(.system(size: 40, weight: .bold))
                        .foregroundColor(.white)

                    VStack(alignment: .leading, spacing: 12) {
                        StepRow(number: "1", text: "Open GO Media on your iPhone")
                        StepRow(number: "2", text: "Tap the Ⓟ icon → Link Apple TV")
                        StepRow(number: "3", text: "Enter the code shown on the left")
                    }

                    Spacer().frame(height: 8)

                    Text(statusMessage)
                        .font(.callout)
                        .foregroundColor(isError ? .red : .white.opacity(0.5))

                    if isError {
                        Button("Try Again") { regenerate() }
                            .buttonStyle(.borderedProminent)
                            .tint(.red)
                    }
                }
                .frame(maxWidth: 460)
            }
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
        qrImage = nil
        sessionCode = ""

        Task {
            do {
                let code = try await auth.createTVSession()
                sessionCode = code
                qrImage = generateQR(from: loginURL)
                statusMessage = "Scan the QR code with your phone to sign in"
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

    func generateQR(from string: String) -> UIImage? {
        let context = CIContext()
        let filter = CIFilter.qrCodeGenerator()
        filter.setValue(Data(string.utf8), forKey: "inputMessage")
        filter.setValue("M", forKey: "inputCorrectionLevel")
        guard let output = filter.outputImage else { return nil }
        let scaled = output.transformed(by: CGAffineTransform(scaleX: 10, y: 10))
        guard let cgImg = context.createCGImage(scaled, from: scaled.extent) else { return nil }
        return UIImage(cgImage: cgImg)
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
