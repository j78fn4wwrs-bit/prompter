import SwiftUI
import UIKit

/// Paused-only navigation from the remote: a jog strip plus line/page buttons.
struct RemoteNavigateView: View {
    @ObservedObject var client: RemoteClient
    var onDone: () -> Void

    @State private var lastTranslation: CGFloat = 0
    @State private var pending: CGFloat = 0
    @State private var lastSend = Date.distantPast

    private var playing: Bool { client.state?.isPlaying == true }

    var body: some View {
        NavigationStack {
            VStack(spacing: 14) {
                if playing {
                    banner("The prompter is playing. Pause it to move through the script.")
                }
                jogStrip
                HStack(spacing: 12) {
                    navButton("Line Up", icon: "chevron.up", command: .lineUp)
                    navButton("Line Down", icon: "chevron.down", command: .lineDown)
                }
                .frame(height: 60)
                HStack(spacing: 12) {
                    navButton("Page Up", icon: "chevron.up.2", command: .pageUp)
                    navButton("Page Down", icon: "chevron.down.2", command: .pageDown)
                }
                .frame(height: 60)
            }
            .padding(20)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(LensGlassBackground())
            .disabled(playing)
            .navigationTitle("Navigate")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) { Button("Done") { onDone() } }
            }
        }
    }

    private var jogStrip: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(LinearGradient(colors: [LensGlassColor.secondaryTop, LensGlassColor.secondaryBottom],
                                     startPoint: .top, endPoint: .bottom))
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .strokeBorder(LensGlassColor.rim, lineWidth: 3)
            VStack(spacing: 10) {
                Image(systemName: "chevron.up").font(.title2.bold())
                Text("Drag up or down\nto move through the script")
                    .multilineTextAlignment(.center)
                    .font(.system(size: 17, weight: .semibold))
                Image(systemName: "chevron.down").font(.title2.bold())
            }
            .foregroundStyle(LensGlassColor.secondaryLabelGlyph)
        }
        .frame(maxHeight: .infinity)
        .contentShape(Rectangle())
        .gesture(
            DragGesture(minimumDistance: 2)
                .onChanged { value in
                    // Finger up = further down the script, like dragging the prompter text.
                    let step = lastTranslation - value.translation.height
                    lastTranslation = value.translation.height
                    pending += step
                    // Throttle to about 20 sends per second.
                    if Date().timeIntervalSince(lastSend) >= 0.05 { flush() }
                }
                .onEnded { _ in
                    flush()
                    lastTranslation = 0
                }
        )
        .accessibilityLabel("Scroll strip")
        .accessibilityHint("Drag up or down to move the prompter through the script")
    }

    private func flush() {
        guard pending != 0 else { return }
        client.send(nav: .scrub(points: Double(pending)))
        pending = 0
        lastSend = Date()
    }

    private func navButton(_ title: String, icon: String, command: RemoteNavCommand) -> some View {
        Button {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            client.send(nav: command)
        } label: {
            Label(title, systemImage: icon).labelStyle(.titleAndIcon)
        }
        .buttonStyle(LensGlassButtonStyle(role: .secondary, fontSize: 18, horizontalPadding: 10))
    }
}

/// Full-screen editor for the script on the prompter. Paused only; refuses stale saves.
struct RemoteScriptEditorView: View {
    @ObservedObject var client: RemoteClient
    var onDone: () -> Void

    @State private var text = ""
    @State private var baseRevision: Int?
    @State private var saving = false
    @State private var showConflict = false
    @State private var errorMessage: String?

    private var playing: Bool { client.state?.isPlaying == true }
    private var tooLarge: Bool { text.utf8.count > RemoteLimits.maxScriptBytes }

    var body: some View {
        NavigationStack {
            VStack(spacing: 10) {
                if playing {
                    banner("The prompter is playing. You can keep typing; Save works once it's paused.")
                }
                if let errorMessage {
                    banner(errorMessage)
                }
                if baseRevision == nil {
                    Spacer()
                    ProgressView("Loading script from the prompter…")
                        .foregroundStyle(LensGlassColor.label)
                    Spacer()
                } else {
                    TextEditor(text: $text)
                        .font(.body)
                        .foregroundStyle(LensGlassColor.label)
                        .scrollContentBackground(.hidden)
                        .padding(8)
                        .background(LensGlassColor.card, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .strokeBorder(LensGlassColor.separator, lineWidth: 1))
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(LensGlassBackground())
            .navigationTitle(client.script?.title ?? "Edit Script")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { onDone() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    if saving {
                        ProgressView()
                    } else {
                        Button("Save") { save() }
                            .bold()
                            .disabled(baseRevision == nil || playing || tooLarge)
                    }
                }
            }
            .alert("Script changed on the prompter", isPresented: $showConflict) {
                Button("Reload") { reload() }
                Button("Keep Editing", role: .cancel) {}
            } message: {
                Text("The script was changed on the prompter since you opened it. Reload to get the latest text (your edits here will be lost).")
            }
        }
        .onAppear { reload() }
        .onChange(of: client.script) { _, newScript in
            guard let newScript, baseRevision == nil else { return }
            text = newScript.text
            baseRevision = newScript.revision
        }
        .onChange(of: client.scriptResult) { _, result in
            guard let result else { return }
            saving = false
            switch result.kind {
            case .saved:
                onDone()
            case .conflict:
                showConflict = true
            case .playing:
                errorMessage = "Not saved: the prompter is playing. Pause it, then tap Save again."
            case .tooLarge:
                errorMessage = "This script is too large to edit from the remote (over 1 MB)."
            }
        }
    }

    private func reload() {
        baseRevision = nil
        errorMessage = nil
        client.requestScript()
    }

    private func save() {
        guard let baseRevision else { return }
        saving = true
        errorMessage = nil
        client.sendScriptUpdate(RemoteScriptUpdate(text: text, baseRevision: baseRevision))
        // If the prompter never answers (older build or dropped link), stop spinning.
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(5))
            if saving {
                saving = false
                errorMessage = "No answer from the prompter. Make sure it's running the latest build and still connected."
            }
        }
    }
}

/// Yellow-edged notice used by the remote's navigate and edit screens.
private func banner(_ text: String) -> some View {
    HStack(spacing: 8) {
        Image(systemName: "exclamationmark.triangle.fill")
            .foregroundStyle(LensGlassColor.yellow)
        Text(text)
            .font(.callout.weight(.semibold))
            .foregroundStyle(LensGlassColor.label)
            .fixedSize(horizontal: false, vertical: true)
        Spacer(minLength: 0)
    }
    .padding(12)
    .background(LensGlassColor.card, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous)
        .strokeBorder(LensGlassColor.yellow, lineWidth: 2))
}
