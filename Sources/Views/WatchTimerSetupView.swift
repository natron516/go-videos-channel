import SwiftUI

struct WatchTimerSetupView: View {
    @ObservedObject private var watchTimer = WatchTimerManager.shared
    @Environment(\.dismiss) var dismiss

    let presets = [1, 5, 10, 15, 20, 30]
    @State private var pin = ""
    @State private var showingPin = false
    @State private var selectedMinutes: Int? = nil

    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()
                Color.clear.appBackground()

                if watchTimer.isRunning {
                    runningView
                } else if showingPin {
                    pinEntryView
                } else {
                    setupView
                }
            }
            .navigationTitle("Watch Timer")
            #if !os(tvOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    // MARK: - Setup View
    var setupView: some View {
        List {
            Section {
                ForEach(presets, id: \.self) { minutes in
                    Button {
                        selectedMinutes = minutes
                        showingPin = true
                        pin = ""
                    } label: {
                        HStack {
                            Text("\(minutes) minutes")
                                .foregroundColor(.white)
                            Spacer()
                            Image(systemName: "chevron.right")
                                .foregroundColor(.white.opacity(0.3))
                                .font(.caption)
                        }
                    }
                }
            } header: {
                Text("Select a time limit")
            } footer: {
                Text("When time is up, the app will lock until a parent enters the PIN.")
            }
        }
        #if !os(tvOS)
        .scrollContentBackground(.hidden)
        #endif
    }

    // MARK: - PIN Entry View
    var pinEntryView: some View {
        VStack(spacing: 30) {
            Text("Set a 4-digit PIN")
                .font(.headline)
                .foregroundColor(.white)

            Text("You'll need this to unlock when time's up")
                .font(.subheadline)
                .foregroundColor(.white.opacity(0.5))

            // PIN dots
            HStack(spacing: 20) {
                ForEach(0..<4, id: \.self) { i in
                    ZStack {
                        Circle()
                            .stroke(Color.white.opacity(0.25), lineWidth: 2)
                            .frame(width: 18, height: 18)
                        if i < pin.count {
                            Circle()
                                .fill(Color.orange)
                                .frame(width: 14, height: 14)
                        }
                    }
                }
            }

            // Numpad
            VStack(spacing: 12) {
                ForEach([[1,2,3],[4,5,6],[7,8,9]], id: \.self) { row in
                    HStack(spacing: 12) {
                        ForEach(row, id: \.self) { n in
                            PinButton(label: "\(n)") { tapPin("\(n)") }
                        }
                    }
                }
                HStack(spacing: 12) {
                    PinButton(label: "⌫", isSymbol: true) { backspacePin() }
                    PinButton(label: "0") { tapPin("0") }
                    Button {
                        showingPin = false
                        pin = ""
                        selectedMinutes = nil
                    } label: {
                        Text("Cancel")
                            .font(.system(size: 16, weight: .medium))
                            .foregroundColor(.red)
                            .frame(width: 100, height: 68)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(.top, 40)
    }

    // MARK: - Running View
    var runningView: some View {
        VStack(spacing: 24) {
            ZStack {
                Circle()
                    .stroke(Color.white.opacity(0.15), lineWidth: 8)
                    .frame(width: 140, height: 140)
                Circle()
                    .trim(from: 0, to: watchTimer.progress)
                    .stroke(Color.orange, style: StrokeStyle(lineWidth: 8, lineCap: .round))
                    .frame(width: 140, height: 140)
                    .rotationEffect(.degrees(-90))
                Text(watchTimer.formattedTimeRemaining)
                    .font(.system(size: 32, weight: .bold, design: .rounded))
                    .foregroundColor(.white)
            }

            Button(role: .destructive) {
                watchTimer.stop()
            } label: {
                Text("Cancel Timer")
            }
        }
    }

    // MARK: - Logic

    func tapPin(_ digit: String) {
        guard pin.count < 4 else { return }
        pin.append(digit)
        if pin.count == 4 {
            if let minutes = selectedMinutes {
                watchTimer.start(minutes: minutes, pin: pin)
                dismiss()
            }
        }
    }

    func backspacePin() {
        if !pin.isEmpty { pin.removeLast() }
    }
}

// MARK: - Isolated timer-observing views (prevent full parent re-render)

struct WatchTimerButton: View {
    let action: () -> Void
    @ObservedObject private var watchTimer = WatchTimerManager.shared

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: "timer")
                    .foregroundColor(.orange)
                if watchTimer.isRunning {
                    Text(watchTimer.formattedTimeRemaining)
                        .foregroundColor(.orange)
                } else {
                    Text("Watch Timer")
                }
            }
        }
    }
}

struct WatchTimerMenuLabel: View {
    @ObservedObject private var watchTimer = WatchTimerManager.shared

    var body: some View {
        Label(
            watchTimer.isRunning ? "Watch Timer (\(watchTimer.formattedTimeRemaining))" : "Watch Timer",
            systemImage: "timer"
        )
    }
}
