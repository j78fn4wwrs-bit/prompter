import SwiftUI
import UIKit

/// "Remote" mode: this device controls a prompter on another nearby iPhone or iPad. Free.
struct RemoteControlView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var client = RemoteClient()
    @State private var selected: NearbyPrompter?
    @State private var code = ""

    var body: some View {
        NavigationStack {
            Group {
                if client.status == .connected {
                    controlPad
                } else {
                    pairingList
                }
            }
            .navigationTitle("Remote Control")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Done") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    RemoteStatusBadge(status: client.status)
                }
            }
        }
        .onAppear {
            client.start()
            UIApplication.shared.isIdleTimerDisabled = true
        }
        .onDisappear {
            client.stop()
            UIApplication.shared.isIdleTimerDisabled = false
        }
        .alert("Enter the code", isPresented: Binding(
            get: { selected != nil },
            set: { if !$0 { selected = nil } }
        )) {
            TextField("4-digit code", text: $code)
                .keyboardType(.numberPad)
            Button("Connect") {
                if let selected { client.pair(with: selected, code: code.trimmingCharacters(in: .whitespaces)) }
                selected = nil
                code = ""
            }
            Button("Cancel", role: .cancel) { selected = nil; code = "" }
        } message: {
            Text("Type the 4-digit code shown on \(selected?.name ?? "the prompter").")
        }
    }

    private var pairingList: some View {
        List {
            Section {
                Text("On the prompter device, open a script, tap the remote button and turn on Allow Remote (Pro). Then pick it below and type the code it shows.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            if let error = client.pairingError {
                Section { Text(error).foregroundStyle(.red) }
            }
            Section("Nearby prompters") {
                if client.nearby.isEmpty {
                    HStack(spacing: 10) {
                        ProgressView()
                        Text("Looking for prompters…").foregroundStyle(.secondary)
                    }
                }
                ForEach(client.nearby) { prompter in
                    Button {
                        code = ""
                        selected = prompter
                    } label: {
                        HStack {
                            Image(systemName: "text.alignleft")
                            Text(prompter.name).foregroundStyle(.primary)
                            Spacer()
                            if prompter.name == client.savedHost {
                                Text(client.status == .connecting ? "Reconnecting…" : "Paired")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
            if client.savedHost != nil {
                Section {
                    Button("Forget paired prompter", role: .destructive) { client.forgetPairing() }
                }
            }
        }
    }

    private var controlPad: some View {
        VStack(spacing: 16) {
            VStack(spacing: 4) {
                Text(client.hostName ?? "Prompter")
                    .font(.headline)
                if let state = client.state {
                    Text(state.isPlaying ? "Playing" : "Paused")
                        .font(.subheadline.bold())
                        .foregroundStyle(state.isPlaying ? .green : .orange)
                    Text(String(format: "Speed %.1f", state.speed / 20))
                        .font(.subheadline.monospacedDigit())
                        .foregroundStyle(.secondary)
                    if let title = state.markerTitle {
                        Label(title, systemImage: "bookmark.fill")
                            .font(.subheadline)
                            .lineLimit(1)
                            .foregroundStyle(.orange)
                    }
                }
            }
            .padding(.top, 8)

            bigButton(client.state?.isPlaying == true ? "Pause" : "Play",
                      icon: client.state?.isPlaying == true ? "pause.fill" : "play.fill",
                      tint: .green, command: .playPause)
                .frame(maxHeight: .infinity)

            HStack(spacing: 16) {
                bigButton("Slower", icon: "tortoise.fill", tint: .blue, command: .speedDown)
                bigButton("Faster", icon: "hare.fill", tint: .blue, command: .speedUp)
            }
            .frame(maxHeight: .infinity)

            HStack(spacing: 16) {
                bigButton("Back", icon: "backward.fill", tint: .orange, command: .jumpBack)
                bigButton("Forward", icon: "forward.fill", tint: .orange, command: .jumpForward)
            }
            .frame(maxHeight: .infinity)

            bigButton("Back to Top", icon: "backward.end.fill", tint: .gray, command: .resetToTop)
                .frame(height: 64)
        }
        .padding()
    }

    private func bigButton(_ title: String, icon: String, tint: Color, command: RemoteCommand) -> some View {
        Button {
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            client.send(command)
        } label: {
            Label(title, systemImage: icon)
                .font(.title2.bold())
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .buttonStyle(.borderedProminent)
        .tint(tint)
        .accessibilityLabel(title)
    }
}

/// Small connected / waiting / disconnected pill, used on both devices.
struct RemoteStatusBadge: View {
    let status: RemoteLinkStatus

    var body: some View {
        HStack(spacing: 6) {
            Circle().fill(color).frame(width: 8, height: 8)
            Text(label).font(.caption.bold())
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(.black.opacity(0.55), in: Capsule())
        .foregroundStyle(.white)
        .accessibilityElement(children: .combine)
    }

    private var label: String {
        switch status {
        case .off: return "Remote off"
        case .waiting: return "Waiting"
        case .connecting: return "Connecting…"
        case .connected: return "Connected"
        case .disconnected: return "Disconnected"
        }
    }

    private var color: Color {
        switch status {
        case .connected: return .green
        case .connecting, .waiting: return .yellow
        case .disconnected: return .red
        case .off: return .gray
        }
    }
}
