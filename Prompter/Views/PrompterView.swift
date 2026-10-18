import SwiftUI
import UIKit

struct PrompterView: View {
    let text: String

    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var store: ProStore
    @StateObject private var engine = ScrollEngine()
    @StateObject private var camera = CameraRecorder()

    @AppStorage(PrefKey.speed) private var speed: Double = 60
    @AppStorage(PrefKey.fontSize) private var fontSize: Double = 40
    @AppStorage(PrefKey.mirror) private var mirror: Bool = false
    @AppStorage(PrefKey.textHex) private var textHex: String = "#FFFFFF"
    @AppStorage(PrefKey.backgroundHex) private var backgroundHex: String = "#000000"

    @State private var countdown: Int?
    @State private var countdownTask: Task<Void, Never>?
    @State private var contentHeight: CGFloat = 0
    @State private var dragStartOffset: CGFloat?
    @State private var showControls = true
    @State private var showPaywall = false
    @State private var showColors = false
    @State private var cameraMode = false
    @FocusState private var keyboardFocused: Bool

    /// Reading line sits a third of the way down the screen.
    private let readingLineFraction: CGFloat = 0.33
    private let horizontalPadding: CGFloat = 24

    private var textColor: Color { store.isPro ? Color(hex: textHex) : .white }
    private var backgroundColor: Color { store.isPro ? Color(hex: backgroundHex) : .black }

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
                        .foregroundStyle(.white)
                        .shadow(radius: 8)
                        .transition(.scale.combined(with: .opacity))
                        .id(countdown)
                        .allowsHitTesting(false)
                }
                if showControls && !engine.isPlaying && countdown == nil {
                    controls
                }
            }
            .onAppear { updateMax(height: geo.size.height, lineY: lineY) }
            .onChange(of: contentHeight) { _, _ in updateMax(height: geo.size.height, lineY: lineY) }
            .onChange(of: geo.size) { _, newSize in
                updateMax(height: newSize.height, lineY: newSize.height * readingLineFraction)
            }
        }
        .ignoresSafeArea()
        .statusBarHidden(true)
        .persistentSystemOverlays(.hidden)
        .focusable()
        .focused($keyboardFocused)
        .focusEffectDisabled()
        .onKeyPress { press in handleKey(press) }
        .onAppear {
            engine.speed = speed
            keyboardFocused = true
        }
        .onChange(of: speed) { _, newValue in engine.speed = newValue }
        .onChange(of: engine.isPlaying) { _, playing in
            if !playing && camera.isRecording { camera.stopRecording() }
        }
        .onDisappear {
            countdownTask?.cancel()
            engine.pause()
            camera.stopSession()
        }
        .sheet(isPresented: $showPaywall) {
            PaywallView().environmentObject(store)
        }
        .sheet(isPresented: $showColors) {
            colorSheet
                .presentationDetents([.medium])
        }
        .animation(.easeInOut(duration: 0.2), value: countdown)
        .animation(.easeInOut(duration: 0.2), value: engine.isPlaying)
    }

    // MARK: Layers

    @ViewBuilder
    private var background: some View {
        if cameraMode {
            CameraPreview(session: camera.session)
                .overlay(Color.black.opacity(0.45))
        } else {
            backgroundColor
        }
    }

    private func scriptLayer(size: CGSize, lineY: CGFloat) -> some View {
        Text(text)
            .font(.system(size: CGFloat(fontSize), weight: .semibold))
            .foregroundStyle(textColor)
            .lineSpacing(CGFloat(fontSize) * 0.25)
            .multilineTextAlignment(.leading)
            .frame(width: max(0, size.width - horizontalPadding * 2), alignment: .leading)
            .fixedSize(horizontal: false, vertical: true)
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

    private func readingLine(y: CGFloat, width: CGFloat) -> some View {
        HStack(spacing: 0) {
            Image(systemName: "arrowtriangle.right.fill")
                .font(.system(size: 18))
                .foregroundStyle(Color.red.opacity(0.85))
            Rectangle()
                .fill(Color.red.opacity(0.35))
                .frame(height: 2)
        }
        .frame(width: width)
        .position(x: width / 2, y: y)
        .allowsHitTesting(false)
    }

    private var controls: some View {
        VStack {
            HStack {
                Button { dismiss() } label: {
                    Image(systemName: "xmark").padding(10)
                }
                Spacer()
                Button { engine.reset() } label: {
                    Image(systemName: "backward.end.fill").padding(10)
                }
            }
            .font(.title3.bold())
            .foregroundStyle(.white)
            .padding(.horizontal, 16)
            .padding(.top, 50)

            Spacer()

            if let message = camera.statusMessage {
                Text(message)
                    .font(.footnote)
                    .foregroundStyle(.white)
                    .padding(8)
                    .background(.black.opacity(0.6), in: Capsule())
            }

            VStack(spacing: 14) {
                HStack {
                    Image(systemName: "tortoise.fill")
                    Slider(value: $speed, in: 10...300)
                    Image(systemName: "hare.fill")
                }
                HStack {
                    Image(systemName: "textformat.size.smaller")
                    Slider(value: $fontSize, in: 20...100)
                    Image(systemName: "textformat.size.larger")
                }
                HStack(spacing: 22) {
                    Toggle(isOn: $mirror) {
                        Image(systemName: "arrow.left.and.right.righttriangle.left.righttriangle.right")
                    }
                    .toggleStyle(.button)

                    proButton(icon: cameraMode ? "video.fill" : "video", active: cameraMode) {
                        cameraMode.toggle()
                        if cameraMode { camera.prepare() } else { camera.stopSession() }
                    }
                    proButton(icon: "paintpalette", active: false) {
                        showColors = true
                    }

                    Spacer()

                    Button { togglePlay() } label: {
                        Image(systemName: cameraMode ? "record.circle" : "play.circle.fill")
                            .font(.system(size: 44))
                            .foregroundStyle(cameraMode ? Color.red : Color.white)
                    }
                }
                .font(.title2)
                Text("Tap anywhere to start or pause. Drag to move.")
                    .font(.caption2)
                    .foregroundStyle(.white.opacity(0.7))
            }
            .tint(.white)
            .foregroundStyle(.white)
            .padding(16)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 20))
            .environment(\.colorScheme, .dark)
            .padding(.horizontal, 12)
            .padding(.bottom, 30)
        }
    }

    private func proButton(icon: String, active: Bool, action: @escaping () -> Void) -> some View {
        Button {
            if store.isPro { action() } else { showPaywall = true }
        } label: {
            ZStack(alignment: .topTrailing) {
                Image(systemName: icon)
                    .foregroundStyle(active ? Color.red : Color.white)
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
                ColorPicker("Text", selection: Binding(
                    get: { Color(hex: textHex) },
                    set: { textHex = $0.hexString() }
                ), supportsOpacity: false)
                ColorPicker("Background", selection: Binding(
                    get: { Color(hex: backgroundHex) },
                    set: { backgroundHex = $0.hexString() }
                ), supportsOpacity: false)
                Button("Reset to white on black") {
                    textHex = "#FFFFFF"
                    backgroundHex = "#000000"
                }
            }
            .navigationTitle("Colors")
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    // MARK: Behaviour

    private func updateMax(height: CGFloat, lineY: CGFloat) {
        // Stop when the last line reaches the reading line.
        engine.maxOffset = max(0, contentHeight - CGFloat(fontSize))
        if engine.offset > engine.maxOffset { engine.offset = engine.maxOffset }
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
            if cameraMode && store.isPro {
                camera.startRecording()
            }
        }
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

    /// Hardware keyboard / Bluetooth clicker (Pro). Most clickers send arrows or page up/down.
    private func handleKey(_ press: KeyPress) -> KeyPress.Result {
        guard store.isPro else { return .ignored }
        let step = CGFloat(fontSize) * 3
        if press.key == .space || press.key == .return {
            togglePlay()
            return .handled
        }
        if press.key == .downArrow || press.key == .rightArrow || press.key == .pageDown {
            engine.nudge(by: step)
            return .handled
        }
        if press.key == .upArrow || press.key == .leftArrow || press.key == .pageUp {
            engine.nudge(by: -step)
            return .handled
        }
        if press.key == .escape {
            dismiss()
            return .handled
        }
        return .ignored
    }
}
