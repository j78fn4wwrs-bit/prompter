import SwiftUI
import UIKit

/// "Remote" mode: this device controls a prompter on another nearby iPhone or iPad. Free.
struct RemoteControlView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var client = RemoteClient()
    @State private var selected: NearbyPrompter?
    @State private var code = ""
    @State private var showMarkers = false
    /// Remote look: Dark (navy, white, yellow) by default, or Light. Independent of the system setting.
    @AppStorage("remote.appearanceDark") private var darkAppearance: Bool = true

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
                    HStack(spacing: 10) {
                        Button { darkAppearance.toggle() } label: {
                            Image(systemName: darkAppearance ? "sun.max.fill" : "moon.fill")
                                .foregroundStyle(darkAppearance ? LensGlassColor.yellow : LensGlassColor.label)
                        }
                        .accessibilityLabel(darkAppearance ? "Switch to light look" : "Switch to dark look")
                        RemoteStatusBadge(status: client.status)
                    }
                }
            }
            .sheet(isPresented: $showMarkers) {
                markersSheet
                    .preferredColorScheme(darkAppearance ? .dark : .light)
            }
        }
        // The SP/D1 color sets have Light and Dark variants; forcing the scheme gives the
        // navy/white/yellow look (Dark) or the pale-blue/navy look (Light) on every state,
        // including the code alert, whatever the system appearance is.
        .preferredColorScheme(darkAppearance ? .dark : .light)
        .tint(darkAppearance ? LensGlassColor.yellow : LensGlassColor.accent)
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

            HStack(spacing: 10) {
                markerButton("Prev", icon: "chevron.up", command: .previous)
                markerButton("Marker", icon: "bookmark.fill", command: .add)
                markerButton("Next", icon: "chevron.down", command: .next)
            }
            .frame(minHeight: 50, maxHeight: 70)

            HStack(spacing: 10) {
                Button { showMarkers = true } label: {
                    Label("Markers (\(client.state?.markers?.count ?? 0))", systemImage: "list.bullet")
                        .labelStyle(.titleAndIcon)
                }
                .buttonStyle(LensGlassButtonStyle(role: .utility, fontSize: 18))
                .accessibilityLabel("Markers list")
                padButton("Top", icon: "backward.end.fill", role: .utility, fontSize: 18, command: .resetToTop)
                    .accessibilityLabel("Back to Top")
            }
            .frame(minHeight: 50, maxHeight: 62)

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

    private func markerButton(_ title: String, icon: String, command: RemoteMarkerCommand) -> some View {
        Button {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            client.send(marker: command)
            if client.state?.markers == nil {
                // The prompter never sent a marker list: it is running a build without remote markers.
                showMarkers = true
            }
        } label: {
            Label(title, systemImage: icon)
                .labelStyle(.titleAndIcon)
        }
        .buttonStyle(LensGlassButtonStyle(role: .secondary, fontSize: 17, horizontalPadding: 8))
        .accessibilityLabel(command == .add ? "Add marker" : (command == .next ? "Next marker" : "Previous marker"))
    }

    private var markersSheet: some View {
        NavigationStack {
            List {
                let markers = client.state?.markers ?? []
                if markers.isEmpty {
                    Text(client.state?.markers == nil
                         ? "The prompter isn't sending markers. Update Steady Prompter on the prompter device (run the latest build there), then reconnect."
                         : "No markers yet. Tap Marker to add one at the reading line.")
                        .foregroundStyle(LensGlassColor.secondaryLabel)
                        .listRowBackground(LensGlassColor.card)
                }
                ForEach(markers) { marker in
                    let isCurrent = marker.key == client.state?.currentMarkerKey
                    Button {
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        client.send(marker: .jump(key: marker.key))
                    } label: {
                        HStack {
                            Image(systemName: isCurrent ? "bookmark.fill" : "bookmark")
                                .foregroundStyle(LensGlassColor.yellow)
                            Text(marker.name)
                                .font(.body.weight(isCurrent ? .bold : .regular))
                                .foregroundStyle(LensGlassColor.label)
                                .lineLimit(2)
                            Spacer()
                            if marker.isEstimate {
                                Text("~" + Timecode.format(marker.seconds))
                                    .font(.footnote.monospacedDigit().italic())
                                    .foregroundStyle(LensGlassColor.secondaryLabel)
                            } else {
                                Text(Timecode.format(marker.seconds))
                                    .font(.footnote.monospacedDigit().weight(.semibold))
                                    .foregroundStyle(LensGlassColor.label)
                            }
                        }
                    }
                    .listRowBackground(isCurrent ? LensGlassColor.yellow.opacity(0.22) : LensGlassColor.card)
                    .accessibilityLabel(isCurrent ? "\(marker.name), current" : marker.name)
                }
            }
            .scrollContentBackground(.hidden)
            .background(LensGlassBackground())
            .navigationTitle("Markers")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) { Button("Done") { showMarkers = false } }
            }
        }
        .presentationDetents([.medium, .large])
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
