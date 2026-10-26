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
            .navigationTitle("Remote")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Done") { dismiss() }
                        .tint(LensGlassColor.accent)
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
                Text("On the prompter device, open a script, tap Remote and turn on Allow Remote (Pro). Then pick it below and type the code it shows.")
                    .font(.callout)
                    .foregroundStyle(LensGlassColor.secondaryLabel)
            }
            .listRowBackground(LensGlassColor.card)
            if let error = client.pairingError {
                Section { Text(error).foregroundStyle(.red) }
            }
            Section("Nearby prompters") {
                if client.nearby.isEmpty {
                    HStack(spacing: 10) {
                        ProgressView()
                        Text("Looking for prompters…").foregroundStyle(LensGlassColor.secondaryLabel)
                    }
                }
                ForEach(client.nearby) { prompter in
                    Button {
                        code = ""
                        selected = prompter
                    } label: {
                        HStack {
                            LensGlassIconTile(systemName: "text.alignleft", size: 32, symbolSize: 14)
                            Text(prompter.name).foregroundStyle(LensGlassColor.label)
                            Spacer()
                            if prompter.name == client.savedHost {
                                Text(client.status == .connecting ? "Reconnecting…" : "Paired")
                                    .font(.caption).foregroundStyle(LensGlassColor.secondaryLabel)
                            }
                        }
                    }
                    .listRowBackground(LensGlassColor.card)
                }
            }
            .listRowBackground(LensGlassColor.card)
            if client.savedHost != nil {
                Section {
                    Button("Forget paired prompter", role: .destructive) { client.forgetPairing() }
                }
                .listRowBackground(LensGlassColor.card)
            }
        }
        .scrollContentBackground(.hidden)
        .background(LensGlassBackground())
    }

    private var controlPad: some View {
        let playing = client.state?.isPlaying == true
        return VStack(spacing: 14) {
            padHeader
                .padding(.top, 8)

            padButton(playing ? "Pause" : "Play",
                      icon: playing ? "pause.fill" : "play.fill",
                      role: .primary, fontSize: 34, command: .playPause)
                .frame(minHeight: 72, maxHeight: 112)

            HStack(spacing: 14) {
                padButton("Slower", icon: "tortoise.fill", role: .secondary, fontSize: 24, command: .speedDown)
                padButton("Faster", icon: "hare.fill", role: .secondary, fontSize: 24, command: .speedUp)
            }
            .frame(minHeight: 60, maxHeight: 92)

            HStack(spacing: 14) {
                padButton("Back", icon: "backward.fill", role: .secondary, fontSize: 24, command: .jumpBack)
                padButton("Forward", icon: "forward.fill", role: .secondary, fontSize: 24, command: .jumpForward)
            }
            .frame(minHeight: 60, maxHeight: 92)

            padButton("Back to Top", icon: "backward.end.fill", role: .utility, fontSize: 22, command: .resetToTop)
                .frame(minHeight: 50, maxHeight: 66)

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 12)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(padBackground)
    }

    private var padBackground: some View {
        LinearGradient(colors: [LensGlassColor.backgroundTop, LensGlassColor.backgroundBottom],
                       startPoint: .top, endPoint: .bottom)
            .ignoresSafeArea()
    }

    private var padHeader: some View {
        ZStack {
            LensRingWatermark()
            VStack(spacing: 8) {
                Text(client.hostName ?? "Prompter")
                    .font(.system(size: 26, weight: .bold))
                    .foregroundStyle(LensGlassColor.label)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                if let state = client.state {
                    stateDetails(state)
                }
            }
            .padding(.vertical, 8)
        }
        .frame(maxWidth: .infinity)
    }

    @ViewBuilder
    private func stateDetails(_ state: RemoteState) -> some View {
        Text(state.isPlaying ? "PLAYING" : "PAUSED")
            .font(.system(size: 14, weight: .bold))
            .tracking(0.5)
            .foregroundStyle(LensGlassColor.label)
            .padding(.horizontal, 12)
            .frame(height: 26)
            .background(LensGlassColor.yellow.opacity(0.3), in: Capsule())
            .accessibilityLabel(state.isPlaying ? "Playing" : "Paused")
        Label(String(format: "Speed %.1f", state.speed / 20), systemImage: "gauge.with.needle")
            .font(.system(size: 19, weight: .semibold).monospacedDigit())
            .foregroundStyle(LensGlassColor.secondaryLabel)
        if let title = state.markerTitle {
            Label(title, systemImage: "bookmark.fill")
                .font(.system(size: 16, weight: .semibold))
                .lineLimit(1)
                .foregroundStyle(LensGlassColor.label)
        }
    }

    private func padButton(_ title: String, icon: String, role: LensGlassRole,
                           fontSize: CGFloat, command: RemoteCommand) -> some View {
        Button {
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            client.send(command)
        } label: {
            Label(title, systemImage: icon)
                .labelStyle(.titleAndIcon)
        }
        .buttonStyle(LensGlassButtonStyle(role: role, fontSize: fontSize))
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
