import SwiftUI

struct WatchTimerLockView: View {
    @ObservedObject private var watchTimer = WatchTimerManager.shared

    @State private var entered = ""
    @State private var shaking = false
    @State private var showError = false

    var body: some View {
        ZStack {
            // Solid black background - blocks everything behind
            Color.black.ignoresSafeArea()
            Color.clear.appBackground()

            #if os(tvOS)
            tvOSLayout
            #else
            iOSLayout
            #endif
        }
        // Block all interaction with views behind this
        .contentShape(Rectangle())
        #if os(tvOS)
        .focusSection()
        #endif
    }

    // MARK: - tvOS Layout (larger, focus-friendly)
    #if os(tvOS)
    var tvOSLayout: some View {
        HStack(spacing: 100) {
            // Left side - message
            VStack(spacing: 36) {
                ZStack {
                    Circle()
                        .fill(Color.orange.opacity(0.15))
                        .frame(width: 120, height: 120)
                    Image(systemName: "timer")
                        .font(.system(size: 56, weight: .semibold))
                        .foregroundColor(.orange)
                }

                Text("Time's Up!")
                    .font(.system(size: 48, weight: .bold))
                    .foregroundColor(.white)

                Text(showError ? "Incorrect PIN — try again" : "Enter PIN to unlock")
                    .font(.title3)
                    .foregroundColor(showError ? .red : .white.opacity(0.5))

                // PIN dots
                HStack(spacing: 24) {
                    ForEach(0..<4, id: \.self) { i in
                        ZStack {
                            Circle()
                                .stroke(Color.white.opacity(0.25), lineWidth: 3)
                                .frame(width: 24, height: 24)
                            if i < entered.count {
                                Circle()
                                    .fill(Color.orange)
                                    .frame(width: 18, height: 18)
                            }
                        }
                    }
                }
                .offset(x: shaking ? -12 : 0)
                .animation(shaking ? .easeInOut(duration: 0.07).repeatCount(5, autoreverses: true) : .default, value: shaking)
            }
            .frame(width: 400)

            // Right side - numpad
            VStack(spacing: 20) {
                ForEach([[1,2,3],[4,5,6],[7,8,9]], id: \.self) { row in
                    HStack(spacing: 20) {
                        ForEach(row, id: \.self) { n in
                            Button { tap("\(n)") } label: {
                                Text("\(n)")
                                    .font(.system(size: 36, weight: .semibold, design: .rounded))
                                    .foregroundColor(.white)
                                    .frame(width: 120, height: 90)
                                    .background(
                                        RoundedRectangle(cornerRadius: 16)
                                            .fill(Color.white.opacity(0.08))
                                    )
                            }
                            .buttonStyle(.card)
                        }
                    }
                }
                HStack(spacing: 20) {
                    Button { backspace() } label: {
                        Text("⌫")
                            .font(.system(size: 28, weight: .medium))
                            .foregroundColor(.white)
                            .frame(width: 120, height: 90)
                            .background(
                                RoundedRectangle(cornerRadius: 16)
                                    .fill(Color.white.opacity(0.08))
                            )
                    }
                    .buttonStyle(.card)

                    Button { tap("0") } label: {
                        Text("0")
                            .font(.system(size: 36, weight: .semibold, design: .rounded))
                            .foregroundColor(.white)
                            .frame(width: 120, height: 90)
                            .background(
                                RoundedRectangle(cornerRadius: 16)
                                    .fill(Color.white.opacity(0.08))
                            )
                    }
                    .buttonStyle(.card)

                    Color.clear.frame(width: 120, height: 90)
                }
            }
            .focusSection()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    #endif

    // MARK: - iOS Layout
    #if !os(tvOS)
    var iOSLayout: some View {
        VStack(spacing: 36) {
            ZStack {
                Circle()
                    .fill(Color.orange.opacity(0.15))
                    .frame(width: 100, height: 100)
                Image(systemName: "timer")
                    .font(.system(size: 44, weight: .semibold))
                    .foregroundColor(.orange)
            }

            VStack(spacing: 8) {
                Text("Time's Up!")
                    .font(.system(size: 32, weight: .bold))
                    .foregroundColor(.white)

                Text(showError ? "Incorrect PIN — try again" : "Enter PIN to unlock")
                    .font(.subheadline)
                    .foregroundColor(showError ? .red : .white.opacity(0.5))
            }

            // PIN dots
            HStack(spacing: 20) {
                ForEach(0..<4, id: \.self) { i in
                    ZStack {
                        Circle()
                            .stroke(Color.white.opacity(0.25), lineWidth: 2)
                            .frame(width: 18, height: 18)
                        if i < entered.count {
                            Circle()
                                .fill(Color.orange)
                                .frame(width: 14, height: 14)
                                .transition(.scale.combined(with: .opacity))
                        }
                    }
                    .animation(.spring(response: 0.25, dampingFraction: 0.6), value: entered.count)
                }
            }
            .offset(x: shaking ? -12 : 0)
            .animation(shaking ? .easeInOut(duration: 0.07).repeatCount(5, autoreverses: true) : .default, value: shaking)

            // Numpad
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
        }
        .padding()
    }
    #endif

    // MARK: - Logic

    func tap(_ digit: String) {
        guard entered.count < 4 else { return }
        entered.append(digit)
        if entered.count == 4 {
            if watchTimer.checkPin(entered) {
                watchTimer.unlock()
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
