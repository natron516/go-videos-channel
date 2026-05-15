import SwiftUI
import FirebaseFirestore

private let SERMON_PIN_FALLBACK = "1776"

struct PinLockView: View {
    let onUnlock: () -> Void

    @State private var entered = ""
    @State private var shaking = false
    @State private var showError = false
    @State private var activePin: String = SERMON_PIN_FALLBACK
    @State private var pinReady: Bool = false

    private func fetchPin() {
        // Enable the numpad immediately with the fallback so it never freezes
        pinReady = true
        // Then silently update from Firestore if a PIN has been set
        let db = Firestore.firestore()
        db.collection("config").document("app").getDocument { snap, error in
            guard error == nil,
                  let pin = snap?.data()?["sermon_pin"] as? String,
                  !pin.isEmpty else { return }
            DispatchQueue.main.async { self.activePin = pin }
        }
    }

    var header: some View {
        VStack(spacing: 16) {
            ZStack {
                Circle()
                    .fill(Color.white.opacity(0.08))
                    .frame(width: 80, height: 80)
                Image(systemName: showError ? "lock.slash.fill" : "lock.fill")
                    .font(.system(size: 32, weight: .semibold))
                    .foregroundColor(showError ? .red : .white.opacity(0.85))
                    .animation(.easeInOut(duration: 0.2), value: showError)
            }

            Text("Sermons")
                .font(.system(size: 28, weight: .bold))
                .foregroundColor(.white)

            Text(showError ? "Incorrect PIN — try again" : "Enter your PIN to continue")
                .font(.system(size: 16))
                .foregroundColor(showError ? .red : .white.opacity(0.5))
                .animation(.easeInOut(duration: 0.2), value: showError)
        }
    }

    var dots: some View {
        HStack(spacing: 20) {
            ForEach(0..<4, id: \.self) { i in
                ZStack {
                    Circle()
                        .stroke(Color.white.opacity(0.25), lineWidth: 2)
                        .frame(width: 18, height: 18)
                    if i < entered.count {
                        Circle()
                            .fill(Color.white)
                            .frame(width: 14, height: 14)
                            .transition(.scale.combined(with: .opacity))
                    }
                }
                .animation(.spring(response: 0.25, dampingFraction: 0.6), value: entered.count)
            }
        }
        .offset(x: shaking ? -12 : 0)
        .animation(shaking ? .easeInOut(duration: 0.07).repeatCount(5, autoreverses: true) : .default, value: shaking)
    }

    var numpad: some View {
        VStack(spacing: 14) {
            ForEach([[1,2,3],[4,5,6],[7,8,9]], id: \.self) { row in
                HStack(spacing: 14) {
                    ForEach(row, id: \.self) { n in
                        PinButton(label: "\(n)") { tap("\(n)") }
                    }
                }
            }
            HStack(spacing: 14) {
                PinButton(label: "⌫", isSymbol: true) { backspace() }
                PinButton(label: "0") { tap("0") }
                Color.clear.frame(width: 100, height: 68)
            }
        }
        .opacity(pinReady ? 1 : 0.35)
        .allowsHitTesting(pinReady)
        .overlay(
            Group {
                if !pinReady {
                    ProgressView().tint(.white.opacity(0.5)).scaleEffect(1.5)
                }
            }
        )
    }

    var body: some View {
        ZStack {
            // Starry background — same as every other screen
            Color.black.ignoresSafeArea()
            Color.clear.appBackground()

            #if os(tvOS)
            HStack(spacing: 100) {
                VStack(spacing: 36) {
                    header
                    dots
                }
                .frame(width: 320)
                numpad
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .focusSection()
            #else
            VStack(spacing: 44) {
                header
                dots
                numpad
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding()
            #endif
        }
        .onAppear { fetchPin() }
    }

    func tap(_ digit: String) {
        guard entered.count < 4 else { return }
        entered.append(digit)
        if entered.count == 4 {
            if entered == activePin {
                PinUnlockManager.shared.unlock()
                onUnlock()
            } else {
                shaking = true
                showError = true
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                    shaking = false
                    entered = ""
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                        showError = false
                    }
                }
            }
        }
    }

    func backspace() {
        if !entered.isEmpty { entered.removeLast() }
        showError = false
    }
}

// Suppresses tvOS card shadow, scale, and system highlight
private struct PinPlainButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
    }
}

// Label is its own view so @Environment(\.isFocused) correctly reflects
// the button’s focus state (tvOS sets isFocused on the label, not the parent)
private struct PinButtonLabel: View {
    let label: String
    let isSymbol: Bool
    @Environment(\.isFocused) var isFocused

    var body: some View {
        Text(label)
            .font(isSymbol
                  ? .system(size: 22, weight: .medium)
                  : .system(size: 28, weight: .semibold, design: .rounded))
            .foregroundColor(.white)
            .frame(width: 100, height: 68)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.white.opacity(isFocused ? 0.18 : 0.08))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Color.white.opacity(isFocused ? 1.0 : 0.2),
                            lineWidth: isFocused ? 5 : 1)
            )
            .animation(.easeInOut(duration: 0.1), value: isFocused)
    }
}

struct PinButton: View {
    let label: String
    var isSymbol: Bool = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            PinButtonLabel(label: label, isSymbol: isSymbol)
        }
        .buttonStyle(PinPlainButtonStyle())
    }
}
