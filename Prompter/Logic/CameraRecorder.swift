import Foundation
import AVFoundation
import Photos
import SwiftUI
import UIKit
import Combine

/// Front-camera video + mic recording, saved to Photos when finished. (Pro)
final class CameraRecorder: NSObject, ObservableObject, AVCaptureFileOutputRecordingDelegate {
    @Published private(set) var isRecording: Bool = false
    @Published private(set) var isReady: Bool = false
    @Published var statusMessage: String?

    let session = AVCaptureSession()
    private let movieOutput = AVCaptureMovieFileOutput()
    private let sessionQueue = DispatchQueue(label: "prompter.camera.session")
    private var configured = false
    private var videoDevice: AVCaptureDevice?
    private weak var previewLayer: AVCaptureVideoPreviewLayer?
    private var rotationCoordinator: AVCaptureDevice.RotationCoordinator?
    private var rotationObservations: [NSKeyValueObservation] = []
    private var interruptionObservers: [NSObjectProtocol] = []
    /// Latest upright angle for the movie file. Read on the main queue.
    private var captureAngle: CGFloat?
    /// The coordinator only measures a preview that is already in a window.
    private var previewInWindow = false

    /// True while iOS has paused the camera (e.g. Split View / Slide Over on iPads
    /// without multitasking camera access, or another app took the camera).
    @Published private(set) var isInterrupted: Bool = false

    override init() {
        super.init()
        let center = NotificationCenter.default
        interruptionObservers.append(center.addObserver(forName: AVCaptureSession.wasInterruptedNotification,
                                                        object: session, queue: .main) { [weak self] note in
            self?.handleInterruption(note)
        })
        interruptionObservers.append(center.addObserver(forName: AVCaptureSession.interruptionEndedNotification,
                                                        object: session, queue: .main) { [weak self] _ in
            guard let self else { return }
            self.isInterrupted = false
            self.statusMessage = nil
            if let angle = self.rotationCoordinator?.videoRotationAngleForHorizonLevelPreview {
                self.applyPreviewAngle(angle)
            }
        })
    }

    deinit {
        interruptionObservers.forEach { NotificationCenter.default.removeObserver($0) }
        rotationObservations.forEach { $0.invalidate() }
    }

    private func handleInterruption(_ note: Notification) {
        isInterrupted = true
        // userInfo stores an NSNumber. intValue is Int32; InterruptionReason.RawValue is Int.
        let reason = (note.userInfo?[AVCaptureSessionInterruptionReasonKey] as? NSNumber)
            .flatMap { AVCaptureSession.InterruptionReason(rawValue: $0.integerValue) }
        if reason == .videoDeviceNotAvailableWithMultipleForegroundApps {
            statusMessage = "The camera pauses in Split View or Slide Over on this iPad. Make Steady Prompter full screen to record."
        } else {
            statusMessage = "The camera is paused by iOS. Recording will resume when it's available."
        }
        if isRecording { stopRecording() }
    }

    /// Called once the preview layer is installed in a window. A coordinator created
    /// before that never reports a preview angle, so the preview stays sideways.
    func attachPreview(_ layer: AVCaptureVideoPreviewLayer) {
        if previewLayer !== layer {
            rotationObservations.forEach { $0.invalidate() }
            rotationObservations.removeAll()
            rotationCoordinator = nil
        }
        previewLayer = layer
        previewInWindow = true
        setupRotation()
    }

    /// iOS 17+ rotation handling: keeps the preview level and records upright video
    /// in every iPad/iPhone orientation (including landscape front cameras on iPad).
    /// Both angles are KVO-compliant and the callbacks arrive on the main queue.
    private func setupRotation() {
        guard previewInWindow, let device = videoDevice, let layer = previewLayer else { return }
        if rotationCoordinator == nil {
            let coordinator = AVCaptureDevice.RotationCoordinator(device: device, previewLayer: layer)
            rotationCoordinator = coordinator
            rotationObservations.append(
                coordinator.observe(\.videoRotationAngleForHorizonLevelPreview, options: [.new]) { [weak self] coord, _ in
                    self?.applyPreviewAngle(coord.videoRotationAngleForHorizonLevelPreview)
                }
            )
            rotationObservations.append(
                coordinator.observe(\.videoRotationAngleForHorizonLevelCapture, options: [.new]) { [weak self] coord, _ in
                    self?.captureAngle = coord.videoRotationAngleForHorizonLevelCapture
                }
            )
        }
        guard let coordinator = rotationCoordinator else { return }
        // KVO reports later changes only. Apply the current angles or the preview
        // stays sideways until the device rotates.
        applyPreviewAngle(coordinator.videoRotationAngleForHorizonLevelPreview)
        captureAngle = coordinator.videoRotationAngleForHorizonLevelCapture
        if previewLayer?.connection == nil {
            DispatchQueue.main.async { [weak self] in
                guard let self, let coordinator = self.rotationCoordinator else { return }
                self.applyPreviewAngle(coordinator.videoRotationAngleForHorizonLevelPreview)
            }
        }
    }

    private func applyPreviewAngle(_ angle: CGFloat) {
        guard let connection = previewLayer?.connection,
              connection.isVideoRotationAngleSupported(angle) else { return }
        connection.videoRotationAngle = angle
    }

    func prepare() {
        Task { @MainActor in
            let videoOK = await AVCaptureDevice.requestAccess(for: .video)
            let audioOK = await AVCaptureDevice.requestAccess(for: .audio)
            guard videoOK else {
                self.statusMessage = "Camera access is off. Turn it on in Settings > Steady Prompter."
                return
            }
            if !audioOK {
                self.statusMessage = "Microphone is off, so recordings will be silent."
            }
            self.sessionQueue.async { [weak self] in
                self?.configureAndStart(withAudio: audioOK)
            }
        }
    }

    private func configureAndStart(withAudio: Bool) {
        if !configured {
            session.beginConfiguration()
            session.sessionPreset = .high
            if session.isMultitaskingCameraAccessSupported {
                session.isMultitaskingCameraAccessEnabled = true
            }
            if let camera = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .front),
               let input = try? AVCaptureDeviceInput(device: camera),
               session.canAddInput(input) {
                session.addInput(input)
                videoDevice = camera
            }
            if withAudio,
               let mic = AVCaptureDevice.default(for: .audio),
               let micInput = try? AVCaptureDeviceInput(device: mic),
               session.canAddInput(micInput) {
                session.addInput(micInput)
            }
            if session.canAddOutput(movieOutput) {
                session.addOutput(movieOutput)
            }
            if let connection = movieOutput.connection(with: .video) {
                if connection.isVideoMirroringSupported {
                    connection.automaticallyAdjustsVideoMirroring = false
                    connection.isVideoMirrored = true
                }
            }
            session.commitConfiguration()
            configured = true
        }
        if !session.isRunning {
            session.startRunning()
        }
        DispatchQueue.main.async {
            self.isReady = true
            self.setupRotation()
        }
    }

    func stopSession() {
        sessionQueue.async { [weak self] in
            guard let self else { return }
            if self.movieOutput.isRecording { self.movieOutput.stopRecording() }
            if self.session.isRunning { self.session.stopRunning() }
        }
    }

    func startRecording() {
        guard !isInterrupted else { return }
        let angle = captureAngle ?? rotationCoordinator?.videoRotationAngleForHorizonLevelCapture
        sessionQueue.async { [weak self] in
            guard let self, self.configured, !self.movieOutput.isRecording else { return }
            if let angle, let connection = self.movieOutput.connection(with: .video),
               connection.isVideoRotationAngleSupported(angle) {
                connection.videoRotationAngle = angle
            }
            let url = FileManager.default.temporaryDirectory
                .appendingPathComponent("prompter-\(UUID().uuidString).mov")
            self.movieOutput.startRecording(to: url, recordingDelegate: self)
            DispatchQueue.main.async { self.isRecording = true }
        }
    }

    func stopRecording() {
        sessionQueue.async { [weak self] in
            guard let self, self.movieOutput.isRecording else { return }
            self.movieOutput.stopRecording()
        }
    }

    // MARK: AVCaptureFileOutputRecordingDelegate

    func fileOutput(_ output: AVCaptureFileOutput,
                    didFinishRecordingTo outputFileURL: URL,
                    from connections: [AVCaptureConnection],
                    error: Error?) {
        DispatchQueue.main.async { self.isRecording = false }
        if let error = error as NSError? {
            let finished = (error.userInfo[AVErrorRecordingSuccessfullyFinishedKey] as? Bool) ?? false
            if !finished {
                try? FileManager.default.removeItem(at: outputFileURL)
                DispatchQueue.main.async { self.statusMessage = "Recording failed, so nothing was saved." }
                return
            }
        }
        saveToPhotos(outputFileURL)
    }

    /// Deletes any leftover recordings from a crash or force-quit.
    static func purgeLeftoverRecordings() {
        let fm = FileManager.default
        let dir = fm.temporaryDirectory
        guard let files = try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil) else { return }
        for file in files where file.lastPathComponent.hasPrefix("prompter-") && file.pathExtension == "mov" {
            try? fm.removeItem(at: file)
        }
    }

    private func saveToPhotos(_ url: URL) {
        PHPhotoLibrary.requestAuthorization(for: .addOnly) { status in
            guard status == .authorized || status == .limited else {
                try? FileManager.default.removeItem(at: url)
                DispatchQueue.main.async {
                    self.statusMessage = "Photos access is off, so the video wasn't saved."
                }
                return
            }
            PHPhotoLibrary.shared().performChanges({
                _ = PHAssetChangeRequest.creationRequestForAssetFromVideo(atFileURL: url)
            }, completionHandler: { success, _ in
                try? FileManager.default.removeItem(at: url)
                DispatchQueue.main.async {
                    self.statusMessage = success ? "Saved to Photos." : "Couldn't save the video."
                }
            })
        }
    }
}

/// Live camera preview layer for SwiftUI.
struct CameraPreview: UIViewRepresentable {
    let session: AVCaptureSession
    var onLayerReady: ((AVCaptureVideoPreviewLayer) -> Void)? = nil

    final class PreviewView: UIView {
        override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
        var previewLayer: AVCaptureVideoPreviewLayer { layer as! AVCaptureVideoPreviewLayer }
        var onMovedToWindow: ((AVCaptureVideoPreviewLayer) -> Void)?

        override func didMoveToWindow() {
            super.didMoveToWindow()
            // The layer has no position in the interface until it joins a window.
            guard window != nil else { return }
            onMovedToWindow?(previewLayer)
        }
    }

    func makeUIView(context: Context) -> PreviewView {
        let view = PreviewView()
        view.previewLayer.session = session
        view.previewLayer.videoGravity = .resizeAspectFill
        view.backgroundColor = .black
        view.onMovedToWindow = onLayerReady
        return view
    }

    func updateUIView(_ uiView: PreviewView, context: Context) {
        // The prompter redraws every scroll frame. didMoveToWindow reports the layer;
        // don't attach again from here or the preview angle is rewritten every frame.
        uiView.onMovedToWindow = onLayerReady
    }
}
