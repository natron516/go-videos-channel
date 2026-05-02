import SwiftUI

// Change this to set the PIN
private let SERMON_PIN = "1776"

struct PinLockView: View {
    let onUnlock: () -> Void

    @State private var entered = ""
    @State private var shake = false
    @State private var wrongAttempt = false

    private let digits = [
        ["1","2","3"],
        ["4","5","6"],
        ["7","8","9"],
        ["⌫","0",""]
    ]

    var body: some View {
        VStack(spacing: 48) {
            VStack(spacing: 16) {
                Image(systemName: "lock.fill")
                    .font(.system(size: 60))
                    .foregroundColor(.secondary)

                Text("Enter PIN to access Sermons")
                    .font(.title2)
                    .foregroundColor(.secondary)

                // PIN dots
                HStack(spacing: 20) {
                    ForEach(0..<4, id: \.self) { i in
                        Circle()
                            .fill(i < entered.count ? Color.white : Color.gray.opacity(0.4))
                            .frame(width: 20, height: 20)
                    }
                }
                .offset(x: shake ? -10 : 0)
                .animation(shake ? .easeInOut(duration: 0.05).repeatCount(6, autoreverses: true) : .default, value: shake)

                if wrongAttempt {
                    Text("Incorrect PIN")
                        .foregroundColor(.red)
                        .font(.callout)
                        .transition(.opacity)
                }
            }

            // Number pad
            VStack(spacing: 16) {
                ForEach(digits, id: \.self) { row in
                    HStack(spacing: 16) {
                        ForEach(row, id: \.self) { digit in
                            if digit == "" {
                                Color.clear.frame(width: 100, height: 60)
                            } else {
                                Button {
                                    handleInput(digit)
                                } label: {
                                    Text(digit)
                                        .font(.title.bold())
                                        .frame(width: 100, height: 60)
                                        .background(Color.gray.opacity(0.2))
                                        .cornerRadius(10)
                                }
                                .buttonStyle(.card)
                            }
                        }
                    }
                }
            }
        }
        .padding(60)
    }

    func handleInput(_ digit: String) {
        if digit == "⌫" {
            if !entered.isEmpty { entered.removeLast() }
            wrongAttempt = false
            return
        }

        guard entered.count < 4 else { return }
        entered.append(digit)

        if entered.count == 4 {
            if entered == SERMON_PIN {
                onUnlock()
            } else {
                shake = true
                wrongAttempt = true
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                    shake = false
                    entered = ""
                }
            }
        }
    }
}
