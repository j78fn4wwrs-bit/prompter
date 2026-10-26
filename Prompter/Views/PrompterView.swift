import SwiftUI
import UIKit

struct PrompterView: View {
    let script: Script

    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var store: ProStore
    @StateObject private var engine = ScrollEngine()
    @StateObject private var camera = CameraRecorder()
    @StateObject private var remote = RemoteHost()
    @AppStorage(RemotePrefKey.allowRemote) private var allowRemote: Bool = false

    @AppStorage(PrefKey.speed) private var speed: Double = 60
    @AppStorage(PrefKey.fontSize) private var fontSize: Double = 44
    @AppStorage(PrefKey.mirror) private var mirror: Bool = false
    @AppStorage(PrefKey.prompterMarkerRail) private var showMarkerRail: Bool = true
    @AppStorage(PrefKey.textHex) private var textHex: String = "#FFFFFF"
    @AppStorage(PrefKey.backgroundHex) private var backgroundHex: String = "#000000"

    @State private var countdown: Int?
    @State private var countdownTask: Task<Void, Never>?
    @State private var contentHeight: CGFloat = 0
    @State private var lineTops: [Int: CGFloat] = [:]
    @State private var dragStartOffset: CGFloat?
    @State private var showControls = true
    @State private var paywallFeature: ProFeature?
    @State private var showColors = false
    @State private var showChapters = false
    @State private var showHelp = false
    @State private var showRemotePanel = false
    /// Marker being named right after it was added (main view alert).
    @State private var renameOffset: Int?
    /// Marker being renamed from the Chapters & Markers list (alert inside the sheet).
    @State private var listRenameOffset: Int?
    @State private var renameText = ""
    @State private var cameraMode = false
    @State private var hud: String?
    @State private var hudTask: Task<Void, Never>?
    @State private var viewWidth: CGFloat = 400
    @FocusState private var keyboardFocused: Bool
    /// Only used for the reading-line arrow, not for text size.
    @State private var layoutScale: CGFloat = 1

    // MARK: Text size
    //
    // Old bug: the slider value (20–100) was multiplied by a width-based scale (up to 2.2× on iPad),
    // so the real size reached ~220 pt and the whole script was drawn as ONE giant Text. Past
    // roughly 60% of the slider that single text layer got taller than the GPU's maximum texture
    // size, so iOS drew it downsampled (looked smaller) and then not at all (blank screen).
    // Now: the slider value IS the point size, with a per-device range, and the script is drawn
    // line by line so no single layer gets huge.

    private var isPad: Bool { UIDevice.current.userInterfaceIdiom == .pad }
    private var fontRange: ClosedRange<Double> {
        let base: ClosedRange<Double> = isPad ? 24...120 : 20...80
        // Keep ~6+ average characters per line even in Slide Over / narrow windows.
        let widthCap = max(base.lowerBound, Double(textWidth) / 6)
        return base.lowerBound...min(base.upperBound, widthCap)
    }
    private var scaledFont: CGFloat { CGFloat(min(max(fontSize, fontRange.lowerBound), fontRange.upperBound)) }
    private var textWidth: CGFloat { max(100, viewWidth - max(horizontalPadding, viewWidth * 0.08) * 2) }

    static func scale(for size: CGSize) -> CGFloat {
        min(max(size.width / 430, 0.75), 2.2)
    }

    /// Reading line sits a third of the way down the screen.
    private let readingLineFraction: CGFloat = 0.33
    private let horizontalPadding: CGFloat = 24

    static let freeColorPresets: [(name: String, text: String, background: String)] = [
        ("White on Black", "#FFFFFF", "#000000"),
        ("Black on White", "#000000", "#FFFFFF"),
        ("Yellow on Black", "#FFD60A", "#000000"),
    ]
    private var usingFreePreset: Bool {
        Self.freeColorPresets.contains { $0.text == textHex.uppercased() && $0.background == backgroundHex.uppercased() }
    }
    private var textColor: Color { (store.isPro || usingFreePreset) ? Color(hex: textHex) : .white }
    private var backgroundColor: Color { (store.isPro || usingFreePreset) ? Color(hex: backgroundHex) : .black }

    private var lines: [ScriptLine] { ScriptOutline.lines(script.text) }
    private var markers: [Int] { script.markerOffsets ?? [] }
    private var markedLineIndices: Set<Int> {
        let ls = lines
        return Set(markers.map { ScriptOutline.lineIndex(for: $0, in: ls) })
    }
    private var jumpPoints: [JumpPoint] {
        ScriptOutline.jumpPoints(lines: lines, markers: markers, names: script.markerNames ?? [:])
    }

    /// True when the prompter background is light (e.g. Black on White), so overlay icons go dark.
    private var isLightBackground: Bool {
        if cameraMode { return false }
        let hex = (store.isPro || usingFreePreset) ? backgroundHex : "#000000"
        var s = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.hasPrefix("#") { s.removeFirst() }
        var value: UInt64 = 0
        Scanner(string: s).scanHexInt64(&value)
        let r = Double((value >> 16) & 0xFF) / 255.0
        let g = Double((value >> 8) & 0xFF) / 255.0
        let b = Double(value & 0xFF) / 255.0
        return (0.299 * r + 0.587 * g + 0.114 * b) > 0.6
    }
    private var overlayIconColor: Color { isLightBackground ? Color.black.opacity(0.85) : Color.white }
    private var overlayCircleColor: Color { isLightBackground ? Color.black.opacity(0.10) : Color.white.opacity(0.16) }

    var body: some View {
        GeometryReader { geo in
            let lineY = geo.size.height * readingLineFraction
            ZStack {
                ZStack {
                    background
                    scriptLayer(size: geo.size, lineY: lineY)
                    readingLine(y: lineY, width: geo.size.width)
                }
                .contentShape(Rectangle())
                .onTapGesture { togglePlay() }
                .gesture(scrubGesture)
                if let countdown {
                    Text("\(countdown)")
                        .font(.system(size: 140, weight: .bold, design: .rounded))
                        // Match the script text color so it always contrasts with the
                        // background: dark numbers on light themes, light on dark.
                        .foregroundStyle(textColor)
                        .shadow(color: backgroundColor.opacity(0.6), radius: 8)
                        .transition(.scale.combined(with: .opacity))
                        .id(countdown)
                        .allowsHitTesting(false)
                }
                if showControls && !engine.isPlaying && countdown == nil {
                    controls
                    if showMarkerRail && !markerPoints.isEmpty {
                        markerRail(height: geo.size.height)
                    }
                }
                if let hud {
                    hudView(hud)
                }
                if remote.isRunning {
                    remoteBadge
                }
            }
            .onAppear {
                layoutScale = Self.scale(for: geo.size)
                viewWidth = geo.size.width
                updateMax()
            }
            .onChange(of: contentHeight) { _, _ in updateMax() }
            .onChange(of: geo.size) { _, newSize in
                layoutScale = Self.scale(for: newSize)
                viewWidth = newSize.width
                updateMax()
            }
        }
        .ignoresSafeArea()
        .statusBarHidden(true)
        .persistentSystemOverlays(.hidden)
        .background { commandShortcuts }
        .focusable()
        .focused($keyboardFocused)
        .focusEffectDisabled()
        .onKeyPress(phases: .down) { press in handleKey(press) }
        .onAppear {
            engine.speed = speed
            if fontSize < fontRange.lowerBound || fontSize > fontRange.upperBound {
                fontSize = min(max(fontSize, fontRange.lowerBound), fontRange.upperBound)
            }
            keyboardFocused = true
            if allowRemote && store.isPro { remote.start() }
        }
        .onReceive(remote.commands) { command in handleRemote(command) }
        .onReceive(Timer.publish(every: 1, on: .main, in: .common).autoconnect()) { _ in
            if remote.status == .connected { sendRemoteState() }
        }
        .onChange(of: remote.status) { _, newStatus in
            if newStatus == .connected { sendRemoteState() }
        }
        .onChange(of: store.isPro) { _, nowPro in
            if !nowPro { remote.stop() }
        }
        .onChange(of: speed) { _, newValue in engine.speed = newValue }
        .onChange(of: fontSize) { oldValue, newValue in
            // Keep roughly the same place in the script when the size changes.
            if oldValue > 0 { engine.offset *= CGFloat(newValue / oldValue) }
        }
        .onChange(of: engine.isPlaying) { _, playing in
            if !playing && camera.isRecording { camera.stopRecording() }
            sendRemoteState()
        }
        .onDisappear {
            countdownTask?.cancel()
            hudTask?.cancel()
            engine.reset()
            camera.stopSession()
            remote.stop()
        }
        .sheet(item: $paywallFeature, onDismiss: { keyboardFocused = true }) { feature in
            PaywallView(feature: feature).environmentObject(store)
        }
        .sheet(isPresented: $showColors, onDismiss: { keyboardFocused = true }) {
            colorSheet
                .presentationDetents([.medium, .large])
        }
        .sheet(isPresented: $showChapters, onDismiss: { keyboardFocused = true }) {
            chaptersSheet
                .presentationDetents([.medium, .large])
        }
        .sheet(isPresented: $showHelp, onDismiss: { keyboardFocused = true }) {
            helpSheet
        }
        .sheet(isPresented: showRenameAlert, onDismiss: { keyboardFocused = true }) {
            if let offset = renameOffset {
                MarkerEditSheet(script: script, offset: offset) { renameOffset = nil }
            }
        }
        .animation(.easeInOut(duration: 0.2), value: countdown)
        .animation(.easeInOut(duration: 0.2), value: engine.isPlaying)
        .animation(.easeInOut(duration: 0.2), value: hud)
    }

    // MARK: Layers

    @ViewBuilder
    private var background: some View {
        if cameraMode {
            CameraPreview(session: camera.session, onLayerReady: { layer in
                camera.attachPreview(layer)
            })
                .overlay(Color.black.opacity(0.45))
        } else {
            backgroundColor
        }
    }

    private func scriptLayer(size: CGSize, lineY: CGFloat) -> some View {
        let marked = markedLineIndices
        return VStack(alignment: .leading, spacing: scaledFont * 0.25) {
            ForEach(lines) { line in
                lineView(line, marked: marked.contains(line.id))
                    .onGeometryChange(for: CGFloat.self) { proxy in
                        proxy.frame(in: .named("script")).minY
                    } action: { y in
                        lineTops[line.id] = y
                    }
            }
        }
        .frame(width: textWidth, alignment: .leading)
        .fixedSize(horizontal: false, vertical: true)
        .coordinateSpace(name: "script")
        .onGeometryChange(for: CGFloat.self) { proxy in
            proxy.size.height
        } action: { newHeight in
            contentHeight = newHeight
        }
        .padding(.top, lineY)
        .offset(y: -engine.offset)
        .frame(width: size.width, height: size.height, alignment: .top)
        .clipped()
        .scaleEffect(x: mirror ? -1 : 1, y: 1)
    }

    @ViewBuilder
    private func lineView(_ line: ScriptLine, marked: Bool) -> some View {
        let isHeading = line.headingLevel > 0
        let size = isHeading ? scaledFont * (line.headingLevel == 1 ? 1.15 : 1.05) : scaledFont
        Text(line.text.isEmpty ? " " : line.text)
            .font(.system(size: size, weight: isHeading ? .heavy : .semibold))
            .foregroundStyle(isHeading ? Color.orange : textColor)
            .lineSpacing(scaledFont * 0.25)
            .multilineTextAlignment(.leading)
            .frame(maxWidth: .infinity, alignment: .leading)
            .fixedSize(horizontal: false, vertical: true)
            .overlay(alignment: .leading) {
                if marked {
                    // Subtle marker bar just left of the text.
                    RoundedRectangle(cornerRadius: 2)
                        .fill(Color.orange.opacity(0.8))
                        .frame(width: 4)
                        .padding(.vertical, 2)
                        .offset(x: -12)
                }
            }
    }

    private func readingLine(y: CGFloat, width: CGFloat) -> some View {
        HStack(spacing: 0) {
            Image(systemName: "arrowtriangle.right.fill")
                .font(.system(size: 18 * layoutScale))
                .foregroundStyle(Color.red.opacity(0.85))
            Rectangle()
                .fill(Color.red.opacity(0.35))
                .frame(height: max(2, 2 * layoutScale))
        }
        .frame(width: width)
        .position(x: width / 2, y: y)
        .allowsHitTesting(false)
    }

    private func hudView(_ message: String) -> some View {
        VStack {
            Text(message)
                .font(.headline)
                .foregroundStyle(.white)
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(.black.opacity(0.7), in: Capsule())
                .padding(.top, 60)
            Spacer()
        }
        .transition(.opacity)
        .allowsHitTesting(false)
    }

    private var markerPoints: [JumpPoint] { jumpPoints.filter { $0.kind == .marker } }

    /// The last marker at or above the reading line.
    private var currentMarkerID: String? {
        var found: String?
        for point in markerPoints {
            let top = lineTops[point.lineIndex] ?? 0
            if top <= engine.offset + 1 { found = point.id }
        }
        return found
    }

    /// Slim markers list on the right edge. Only shown while paused (with the other controls),
    /// so it never covers the text during a read. It is not mirrored, like the other controls.
    private func markerRail(height: CGFloat) -> some View {
        let current = currentMarkerID
        return HStack {
            Spacer()
            VStack(alignment: .leading, spacing: 6) {
                Text("Markers")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(overlayIconColor.opacity(0.7))
                    .padding(.horizontal, 6)
                ScrollView {
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(markerPoints) { point in
                            let isCurrent = point.id == current
                            Button {
                                jump(toLine: point.lineIndex, label: point.title)
                            } label: {
                                HStack(spacing: 6) {
                                    Image(systemName: isCurrent ? "bookmark.fill" : "bookmark")
                                        .foregroundStyle(isCurrent ? LensGlassColor.yellow : overlayIconColor)
                                    Text(point.title)
                                        .lineLimit(2)
                                        .multilineTextAlignment(.leading)
                                        .foregroundStyle(overlayIconColor)
                                    Spacer(minLength: 0)
                                    if let offset = Int(point.id.dropFirst()) {
                                        MarkerTimeText(script: script, offset: offset, color: overlayIconColor)
                                    }
                                }
                                .font(.footnote.weight(isCurrent ? .bold : .regular))
                                .padding(.horizontal, 8)
                                .padding(.vertical, 6)
                                .background(
                                    RoundedRectangle(cornerRadius: 10)
                                        .fill(isCurrent ? LensGlassColor.yellow.opacity(0.25) : Color.clear)
                                )
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .contextMenu {
                                Button { beginRailRename(point) } label: {
                                    Label("Edit Marker", systemImage: "pencil")
                                }
                                Button(role: .destructive) { removeMarker(point) } label: {
                                    Label("Delete", systemImage: "trash")
                                }
                            }
                            .accessibilityLabel(isCurrent ? "\(point.title), current" : point.title)
                        }
                    }
                }
            }
            .padding(8)
            .frame(width: min(220, viewWidth * 0.32))
            .frame(maxHeight: height * 0.4)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(isLightBackground ? Color.white.opacity(0.85) : Color.black.opacity(0.55))
            )
            .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(overlayIconColor.opacity(0.2), lineWidth: 1))
            .padding(.trailing, 12)
        }
        .frame(maxHeight: .infinity, alignment: .top)
        .padding(.top, 110)
        .transition(.opacity)
    }

    /// Round overlay button whose icon and fill contrast with the prompter background.
    private func topButton(_ icon: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.title3.bold())
                .foregroundStyle(overlayIconColor)
                .frame(width: 44, height: 44)
                .background(Circle().fill(overlayCircleColor))
                .overlay(Circle().strokeBorder(overlayIconColor.opacity(0.25), lineWidth: 1))
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }

    private var controls: some View {
        VStack {
            HStack(spacing: 8) {
                topButton("xmark", label: "Close") { dismiss() }
                Spacer()
                topButton("keyboard", label: "Keyboard shortcuts") { showHelp = true }
                topButton("list.bullet", label: "Chapters and markers") { showChapters = true }
                topButton(showMarkerRail ? "sidebar.right" : "sidebar.squares.right",
                          label: showMarkerRail ? "Hide markers list" : "Show markers list") {
                    showMarkerRail.toggle()
                }
                topButton("bookmark", label: "Add marker here") { addMarker() }
                topButton("backward.end.fill", label: "Back to top") { engine.reset(); flash("Top") }
            }
            .padding(.horizontal, 16)
            .padding(.top, 50)

            Spacer()
                .allowsHitTesting(false)

            if let message = camera.statusMessage {
                Text(message)
                    .font(.footnote)
                    .foregroundStyle(.white)
                    .padding(8)
                    .background(.black.opacity(0.6), in: Capsule())
            }

            controlBar
                .padding(.horizontal, 12)
                .padding(.bottom, 30)
        }
    }

    // MARK: Lens Glass control bar (D1)

    private var controlBar: some View {
        VStack(spacing: 14) {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 20) {
                    transportControls
                    speedControls
                }
                VStack(spacing: 14) {
                    transportControls
                    speedControls
                }
            }
            fontSizeRow
            toolRow
            if remote.hasPairedRemote {
                Button(role: .destructive) {
                    remote.forgetPairedRemote()
                } label: {
                    Label("Forget paired remote", systemImage: "xmark.circle")
                        .font(.subheadline)
                }
                .foregroundStyle(.red)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            Text("Tap anywhere to start or pause. Drag to move. ⌘/ for keyboard shortcuts.")
                .font(.caption2)
                .foregroundStyle(LensGlassColor.secondaryLabel)
        }
        .tint(LensGlassColor.yellow)
        .foregroundStyle(LensGlassColor.label)
        .padding(18)
        .frame(maxWidth: 760)
        .background(controlBarBackground)
    }

    private var controlBarBackground: some View {
        RoundedRectangle(cornerRadius: 30, style: .continuous)
            .fill(LensGlassColor.card.opacity(0.94))
            .overlay {
                RoundedRectangle(cornerRadius: 30, style: .continuous)
                    .strokeBorder(LensGlassColor.separator, lineWidth: 1.5)
            }
    }

    private var transportControls: some View {
        HStack(spacing: 12) {
            Button { jumpRelative(-1) } label: {
                Image(systemName: "backward.fill")
            }
            .buttonStyle(LensGlassButtonStyle(role: .secondary, fontSize: 20, horizontalPadding: 0))
            .frame(width: 60, height: 60)
            .accessibilityLabel("Back")

            Button { togglePlay() } label: {
                Image(systemName: cameraMode ? "record.circle" : (engine.isPlaying ? "pause.fill" : "play.fill"))
            }
            .buttonStyle(LensGlassButtonStyle(role: .primary, fontSize: 28, horizontalPadding: 0))
            .frame(width: 72, height: 72)
            .accessibilityLabel(cameraMode ? "Record" : (engine.isPlaying ? "Pause" : "Play"))

            Button { jumpRelative(1) } label: {
                Image(systemName: "forward.fill")
            }
            .buttonStyle(LensGlassButtonStyle(role: .secondary, fontSize: 20, horizontalPadding: 0))
            .frame(width: 60, height: 60)
            .accessibilityLabel("Forward")
        }
    }

    private var speedControls: some View {
        HStack(spacing: 10) {
            Button { changeSpeed(by: -10) } label: {
                Image(systemName: "minus")
            }
            .buttonStyle(LensGlassButtonStyle(role: .utility, fontSize: 18, horizontalPadding: 0))
            .frame(width: 48, height: 48)
            .accessibilityLabel("Slower")

            Image(systemName: "gauge.with.needle")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(LensGlassColor.secondaryLabel)
                .accessibilityHidden(true)
            Slider(value: $speed, in: 10...300)
                .frame(minWidth: 60, maxWidth: 300)
                .accessibilityLabel("Speed")
                .accessibilityValue(String(format: "%.1f", speed / 20))
            Text(String(format: "%.1f", speed / 20))
                .font(.system(size: 22, weight: .bold).monospacedDigit())
                .foregroundStyle(LensGlassColor.label)
                .frame(minWidth: 52, alignment: .trailing)
                .accessibilityHidden(true)

            Button { changeSpeed(by: 10) } label: {
                Image(systemName: "plus")
            }
            .buttonStyle(LensGlassButtonStyle(role: .utility, fontSize: 18, horizontalPadding: 0))
            .frame(width: 48, height: 48)
            .accessibilityLabel("Faster")
        }
    }

    private var fontSizeRow: some View {
        HStack {
            Image(systemName: "textformat.size.smaller")
                .accessibilityHidden(true)
            // Left = smaller, right = bigger. The value is the point size.
            Slider(value: fontBinding, in: fontRange)
                .accessibilityLabel("Text size")
            Image(systemName: "textformat.size.larger")
                .accessibilityHidden(true)
        }
        .font(.title3)
        .foregroundStyle(LensGlassColor.secondaryLabel)
    }

    private var toolRow: some View {
        HStack(spacing: 12) {
            Toggle(isOn: $mirror) {
                Image(systemName: "arrow.left.and.right.righttriangle.left.righttriangle.right")
            }
            .toggleStyle(.button)
            .frame(minWidth: 44, minHeight: 44)
            .accessibilityLabel("Mirror")

            proButton(icon: cameraMode ? "video.fill" : "video", active: cameraMode, feature: .camera) {
                cameraMode.toggle()
                if cameraMode { camera.prepare() } else { camera.stopSession() }
            }
            .frame(minWidth: 44, minHeight: 44)
            .accessibilityLabel("Camera")

            // Colors: basic presets are free, custom colors are Pro (inside the sheet).
            Button { showColors = true } label: {
                Image(systemName: "paintpalette")
            }
            .frame(minWidth: 44, minHeight: 44)
            .accessibilityLabel("Colors")

            // Same action as the top bookmark button and the M key.
            Button { addMarker() } label: {
                Image(systemName: "bookmark")
            }
            .frame(minWidth: 44, minHeight: 44)
            .accessibilityLabel("Add marker")

            Spacer()

            remoteButton
        }
        .font(.title2)
    }

    private var remoteButton: some View {
        Button {
            if store.isPro { showRemotePanel = true } else { paywallFeature = .remote }
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "iphone.radiowaves.left.and.right")
                Text("Remote")
                if !store.isPro {
                    Image(systemName: "lock.fill")
                        .font(.system(size: 12, weight: .bold))
                }
            }
        }
        .buttonStyle(LensGlassButtonStyle(role: .secondary, isActive: remote.status == .connected,
                                          fontSize: 18, horizontalPadding: 16))
        .frame(width: 180, height: 52)
        .accessibilityLabel(remote.isRunning ? "Remote, Allow Remote: on" : "Remote, Allow Remote: off")
        .popover(isPresented: $showRemotePanel, arrowEdge: .bottom) {
            remotePanel
                .presentationCompactAdaptation(.popover)
        }
    }

    private var allowRemoteBinding: Binding<Bool> {
        Binding(
            get: { allowRemote },
            set: { on in
                allowRemote = on
                if on {
                    remote.start()
                } else {
                    remote.stop()
                    remote.forgetPairedRemote()
                }
            }
        )
    }

    private var remoteSubtitle: String {
        if !remote.isRunning { return "\(UIDevice.current.name) · off" }
        if remote.status == .connected { return "Connected to your remote" }
        return "\(UIDevice.current.name) · ready to pair · code \(remote.code)"
    }

    private var remotePanel: some View {
        VStack(alignment: .leading, spacing: 16) {
            Toggle(isOn: allowRemoteBinding) {
                HStack(spacing: 10) {
                    Image(systemName: "dot.radiowaves.left.and.right")
                        .foregroundStyle(LensGlassColor.accent)
                        .accessibilityHidden(true)
                    Text("Allow Remote")
                        .font(.system(size: 22, weight: .bold))
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
            }
            .toggleStyle(LensGlassToggleStyle())

            Text(remoteSubtitle)
                .font(.system(size: 15))
                .foregroundStyle(LensGlassColor.secondaryLabel)
                .fixedSize(horizontal: false, vertical: true)

            Divider().overlay(LensGlassColor.separator)

            Button { showRemotePanel = false } label: {
                Label("Done", systemImage: "checkmark")
            }
            .buttonStyle(LensGlassButtonStyle(role: .utility, fontSize: 17))
            .frame(height: 44)
        }
        .foregroundStyle(LensGlassColor.label)
        .padding(24)
        .frame(width: min(400, max(280, viewWidth - 32)))
        .background(LensGlassColor.card)
    }

    /// Top-left pill: pairing code while waiting, connected/disconnected otherwise.
    /// Never blocks touches, and the prompter keeps running if the link drops.
    private var remoteBadge: some View {
        VStack {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    RemoteStatusBadge(status: remote.status)
                    if remote.status != .connected && !engine.isPlaying {
                        Text("Remote code \(remote.code)")
                            .font(.headline.monospacedDigit())
                            .foregroundStyle(.white)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(.black.opacity(0.55), in: Capsule())
                    }
                }
                Spacer()
            }
            .padding(.leading, 16)
            .padding(.top, showControls && !engine.isPlaying ? 100 : 16)
            Spacer()
        }
        .allowsHitTesting(false)
    }

    private var fontBinding: Binding<Double> {
        Binding(get: { Double(scaledFont) }, set: { fontSize = $0 })
    }

    private func proButton(icon: String, active: Bool, feature: ProFeature, action: @escaping () -> Void) -> some View {
        Button {
            if store.isPro { action() } else { paywallFeature = feature }
        } label: {
            ZStack(alignment: .topTrailing) {
                Image(systemName: icon)
                    .foregroundStyle(active ? Color.red : LensGlassColor.label)
                if !store.isPro {
                    Image(systemName: "lock.fill")
                        .font(.system(size: 10))
                        .offset(x: 8, y: -6)
                }
            }
        }
    }

    private var colorSheet: some View {
        NavigationStack {
            Form {
                Section("Presets (free)") {
                    ForEach(Self.freeColorPresets, id: \.name) { preset in
                        Button {
                            textHex = preset.text
                            backgroundHex = preset.background
                        } label: {
                            HStack {
                                Text("Aa")
                                    .font(.headline)
                                    .foregroundStyle(Color(hex: preset.text))
                                    .frame(width: 44, height: 30)
                                    .background(Color(hex: preset.background), in: RoundedRectangle(cornerRadius: 6))
                                    .overlay(RoundedRectangle(cornerRadius: 6).stroke(.gray.opacity(0.4)))
                                Text(preset.name).foregroundStyle(.primary)
                                Spacer()
                                if textHex.uppercased() == preset.text && backgroundHex.uppercased() == preset.background {
                                    Image(systemName: "checkmark").foregroundStyle(.tint)
                                }
                            }
                        }
                    }
                }
                Section("Custom (Pro)") {
                    if store.isPro {
                        ColorPicker("Text", selection: Binding(
                            get: { Color(hex: textHex) },
                            set: { textHex = $0.hexString() }
                        ), supportsOpacity: false)
                        ColorPicker("Background", selection: Binding(
                            get: { Color(hex: backgroundHex) },
                            set: { backgroundHex = $0.hexString() }
                        ), supportsOpacity: false)
                    } else {
                        Button {
                            showColors = false
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { paywallFeature = .colors }
                        } label: {
                            Label("Pick any text and background color", systemImage: "lock.fill")
                        }
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(LensGlassBackground())
            .tint(LensGlassColor.accent)
            .navigationTitle("Colors")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) { Button("Done") { showColors = false } }
            }
        }
    }

    private var chaptersSheet: some View {
        NavigationStack {
            List {
                if jumpPoints.isEmpty {
                    Text("No chapters yet. Start a line with # or ## in the editor, or press M (or the bookmark button) while prompting to add a marker.")
                        .foregroundStyle(.secondary)
                }
                Button { jumpToTop(); showChapters = false } label: {
                    Label("Top", systemImage: "arrow.up.to.line")
                }
                ForEach(Array(jumpPoints.enumerated()), id: \.element.id) { index, point in
                    Button {
                        jump(toLine: point.lineIndex, label: point.title)
                        showChapters = false
                    } label: {
                        HStack {
                            Image(systemName: point.kind == .heading ? "text.book.closed" : "bookmark.fill")
                                .foregroundStyle(.orange)
                            Text(point.title).foregroundStyle(.primary).lineLimit(2)
                            Spacer()
                            if point.kind == .marker, let offset = Int(point.id.dropFirst()) {
                                MarkerTimeText(script: script, offset: offset)
                            }
                            if index < 9 {
                                Text("\(index + 1)").font(.caption.monospaced()).foregroundStyle(.secondary)
                            }
                        }
                    }
                    .swipeActions {
                        if point.kind == .marker {
                            Button(role: .destructive) { removeMarker(point) } label: {
                                Label("Delete", systemImage: "trash")
                            }
                            Button { beginListRename(point) } label: {
                                Label("Edit", systemImage: "pencil")
                            }
                            .tint(LensGlassColor.accent)
                        }
                    }
                    .contextMenu {
                        if point.kind == .marker {
                            Button { beginListRename(point) } label: {
                                Label("Edit Marker", systemImage: "pencil")
                            }
                            Button(role: .destructive) { removeMarker(point) } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(LensGlassBackground())
            .tint(LensGlassColor.accent)
            .sheet(isPresented: showListRenameAlert) {
                if let offset = listRenameOffset {
                    MarkerEditSheet(script: script, offset: offset) { listRenameOffset = nil }
                }
            }
            .navigationTitle("Chapters & Markers")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) { Button("Done") { showChapters = false } }
            }
        }
    }

    private var helpSheet: some View {
        NavigationStack {
            List {
                Section("While prompting (hardware keyboard)") {
                    shortcutRow("Space", "Play / pause")
                    shortcutRow("↑ / ↓", "Speed up / slow down")
                    shortcutRow("⌘+ (or ⌘=) / ⌘−", "Bigger / smaller text")
                    shortcutRow("M", "Add a marker at the reading line")
                    shortcutRow("Tab / Shift-Tab", "Next / previous marker")
                    shortcutRow("← / → or [ / ]", "Previous / next chapter or marker")
                    shortcutRow("1 – 9", "Jump to chapter or marker N")
                    shortcutRow("Home or ⌘↑", "Back to top")
                    shortcutRow("Page Up / Page Down", "Nudge back / forward (clickers)")
                    shortcutRow("Esc", "Exit the prompter")
                    shortcutRow("⌘/", "This help")
                }
                Section {
                    Text("Hold ⌘ on an iPad keyboard to see the shortcut list. Keyboard control is part of Pro.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .scrollContentBackground(.hidden)
            .background(LensGlassBackground())
            .tint(LensGlassColor.accent)
            .navigationTitle("Keyboard Shortcuts")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) { Button("Done") { showHelp = false } }
            }
        }
    }

    private func shortcutRow(_ keys: String, _ action: String) -> some View {
        HStack {
            Text(keys).font(.body.monospaced().bold())
            Spacer()
            Text(action).foregroundStyle(.secondary)
        }
    }

    /// ⌘ shortcuts as hidden buttons, so they appear in iPad's hold-⌘ discoverability overlay.
    /// Plain keys (space, arrows, M, numbers) go through onKeyPress below.
    private var commandShortcuts: some View {
        Group {
            Button("Bigger Text") { keyCommand { changeFont(by: 4) } }
                .keyboardShortcut("+", modifiers: .command)
            Button("Bigger Text ") { keyCommand { changeFont(by: 4) } }
                .keyboardShortcut("=", modifiers: .command)
            Button("Smaller Text") { keyCommand { changeFont(by: -4) } }
                .keyboardShortcut("-", modifiers: .command)
            Button("Back to Top") { keyCommand { jumpToTop() } }
                .keyboardShortcut(.upArrow, modifiers: .command)
            Button("Keyboard Shortcuts") { showHelp = true }
                .keyboardShortcut("/", modifiers: .command)
        }
        .opacity(0)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    // MARK: Behaviour

    private func updateMax() {
        // Stop when the last line reaches the reading line.
        engine.maxOffset = max(0, contentHeight - scaledFont)
        if engine.offset > engine.maxOffset { engine.offset = engine.maxOffset }
    }

    private func flash(_ message: String) {
        hudTask?.cancel()
        hud = message
        hudTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 1_200_000_000)
            if !Task.isCancelled { hud = nil }
        }
    }

    private func togglePlay() {
        if countdown != nil {
            countdownTask?.cancel()
            countdown = nil
            return
        }
        if engine.isPlaying {
            engine.pause()
            showControls = true
        } else {
            startWithCountdown()
        }
    }

    private func startWithCountdown() {
        countdownTask?.cancel()
        countdownTask = Task { @MainActor in
            for n in [3, 2, 1] {
                countdown = n
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                if Task.isCancelled { return }
            }
            countdown = nil
            engine.speed = speed
            engine.play()
            keyboardFocused = true
            if cameraMode && store.isPro {
                camera.startRecording()
            }
        }
    }

    private func changeSpeed(by delta: Double) {
        speed = min(max(speed + delta, 10), 300)
        flash(String(format: "Speed %.1f", speed / 20))
    }

    private func changeFont(by delta: Double) {
        let r = fontRange
        fontSize = min(max(Double(scaledFont) + delta, r.lowerBound), r.upperBound)
        flash("Text \(Int(fontSize)) pt")
    }

    /// Line whose top is at or above the reading line right now.
    private var currentLineIndex: Int {
        var best = 0
        for (index, top) in lineTops where top <= engine.offset + 1 {
            if top >= (lineTops[best] ?? 0) { best = index }
        }
        return best
    }

    private func addMarker() {
        let ls = lines
        let idx = currentLineIndex
        guard ls.indices.contains(idx) else { return }
        guard let offset = script.addMarker(atLineContaining: ls[idx].startOffset) else {
            flash("Marker already here")
            return
        }
        flash("\(script.defaultMarkerName(for: offset)) added")
        // Offer a name only while paused, so a live read (M key, remote) is never interrupted.
        if !engine.isPlaying && countdown == nil {
            renameText = script.defaultMarkerName(for: offset)
            renameOffset = offset
        }
    }

    private func removeMarker(_ point: JumpPoint) {
        guard point.kind == .marker, let offset = Int(point.id.dropFirst()) else { return }
        script.removeMarker(at: offset)
    }

    private func beginListRename(_ point: JumpPoint) {
        guard point.kind == .marker, let offset = Int(point.id.dropFirst()) else { return }
        renameText = script.markerName(for: offset)
        listRenameOffset = offset
    }

    /// Rename from the on-screen rail uses the main-view alert (the sheet is not open).
    private func beginRailRename(_ point: JumpPoint) {
        guard point.kind == .marker, let offset = Int(point.id.dropFirst()) else { return }
        renameText = script.markerName(for: offset)
        renameOffset = offset
    }

    private var showRenameAlert: Binding<Bool> {
        Binding(get: { renameOffset != nil }, set: { if !$0 { renameOffset = nil } })
    }

    private var showListRenameAlert: Binding<Bool> {
        Binding(get: { listRenameOffset != nil }, set: { if !$0 { listRenameOffset = nil } })
    }

    private func jump(toLine index: Int, label: String) {
        guard let top = lineTops[index] else { return }
        engine.jump(to: top)
        flash(label)
    }

    private func jumpToTop() {
        engine.jump(to: 0)
        flash("Top")
    }

    private func jumpRelative(_ direction: Int, markersOnly: Bool = false) {
        let points = markersOnly ? jumpPoints.filter { $0.kind == .marker } : jumpPoints
        guard !points.isEmpty else { flash(markersOnly ? "No markers yet. Press M to add one" : "No chapters or markers"); return }
        let here = engine.offset
        let tops = points.map { lineTops[$0.lineIndex] ?? 0 }
        if direction > 0 {
            if let i = tops.firstIndex(where: { $0 > here + 2 }) {
                jump(toLine: points[i].lineIndex, label: points[i].title)
            } else { flash(markersOnly ? "Last marker" : "Last chapter") }
        } else {
            if let i = tops.lastIndex(where: { $0 < here - 2 }) {
                jump(toLine: points[i].lineIndex, label: points[i].title)
            } else { jumpToTop() }
        }
    }

    private func jumpToPoint(number n: Int) {
        let points = jumpPoints
        guard n >= 1, n <= points.count else { flash("No marker \(n)"); return }
        jump(toLine: points[n - 1].lineIndex, label: "\(n). \(points[n - 1].title)")
    }

    private var scrubGesture: some Gesture {
        DragGesture(minimumDistance: 12)
            .onChanged { value in
                if dragStartOffset == nil {
                    dragStartOffset = engine.offset
                }
                let start = dragStartOffset ?? 0
                engine.offset = min(max(0, start - value.translation.height), engine.maxOffset)
            }
            .onEnded { _ in
                dragStartOffset = nil
            }
    }

    // MARK: Remote control (v1.1)

    /// Remote commands reuse the same actions as the keyboard shortcuts.
    /// Allow Remote is already Pro-gated, so no extra check here.
    private func handleRemote(_ command: RemoteCommand) {
        switch command {
        case .playPause: togglePlay()
        case .speedUp: changeSpeed(by: 10)
        case .speedDown: changeSpeed(by: -10)
        case .jumpBack: remoteJump(-1)
        case .jumpForward: remoteJump(1)
        case .resetToTop: jumpToTop()
        }
        sendRemoteState()
    }

    /// Markers/chapters if the script has any, otherwise about a screenful.
    private func remoteJump(_ direction: Int) {
        if jumpPoints.isEmpty {
            let screen = max(scaledFont * 3, UIScreen.main.bounds.height * 0.6)
            engine.jump(to: engine.offset + CGFloat(direction) * screen)
        } else {
            jumpRelative(direction)
        }
    }

    private var currentPointTitle: String? {
        let points = jumpPoints
        let here = engine.offset + 2
        return points.last(where: { (lineTops[$0.lineIndex] ?? .greatestFiniteMagnitude) <= here })?.title
    }

    private func sendRemoteState() {
        guard remote.status == .connected else { return }
        remote.send(RemoteState(isPlaying: engine.isPlaying || countdown != nil, speed: speed, markerTitle: currentPointTitle))
    }

    /// Runs a keyboard action if Pro (keyboard control is a Pro feature), otherwise explains.
    private func keyCommand(_ action: () -> Void) {
        if store.isPro {
            action()
        } else {
            flash("Keyboard control is a Pro feature")
        }
    }

    /// Plain-key hardware keyboard / Bluetooth clicker handling.
    private func handleKey(_ press: KeyPress) -> KeyPress.Result {
        // ⌘ combos are handled by the hidden shortcut buttons.
        if press.modifiers.contains(.command) { return .ignored }
        if press.key == .escape {
            dismiss()
            return .handled
        }
        if press.characters == "?" {
            showHelp = true
            return .handled
        }
        var handled = true
        let step = scaledFont * 3
        let chars = press.characters.lowercased()
        let action: (() -> Void)?
        switch press.key {
        case .space, .return: action = { togglePlay() }
        case .upArrow: action = { changeSpeed(by: 10) }
        case .downArrow: action = { changeSpeed(by: -10) }
        case .leftArrow: action = { jumpRelative(-1) }
        case .rightArrow: action = { jumpRelative(1) }
        case .tab:
            let back = press.modifiers.contains(.shift)
            action = { jumpRelative(back ? -1 : 1, markersOnly: true) }
        case .pageDown: action = { engine.nudge(by: step) }
        case .pageUp: action = { engine.nudge(by: -step) }
        case .home: action = { jumpToTop() }
        default:
            if chars == "m" {
                action = { addMarker() }
            } else if chars == "[" {
                action = { jumpRelative(-1) }
            } else if chars == "]" {
                action = { jumpRelative(1) }
            } else if chars.count == 1, let n = Int(chars), (1...9).contains(n) {
                action = { jumpToPoint(number: n) }
            } else if chars == "+" || chars == "=" {
                action = { changeFont(by: 4) }
            } else if chars == "-" {
                action = { changeFont(by: -4) }
            } else {
                action = nil
                handled = false
            }
        }
        guard handled, let action else { return .ignored }
        // Key presses arrive on the main thread; hop explicitly to satisfy actor checking.
        DispatchQueue.main.async { keyCommand(action) }
        return .handled
    }
}
