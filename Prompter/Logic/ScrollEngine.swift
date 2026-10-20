import Foundation
import UIKit
import QuartzCore
import Combine

/// Drives smooth scrolling with a CADisplayLink (one step per screen refresh).
/// Also animates marker jumps on the same link, so a jump never fights auto-scroll
/// and the play/pause state is kept.
final class ScrollEngine: NSObject, ObservableObject {
    @Published var offset: CGFloat = 0
    @Published private(set) var isPlaying: Bool = false

    /// Points per second.
    var speed: Double = 60
    var maxOffset: CGFloat = 0

    private var link: CADisplayLink?
    private var lastTimestamp: CFTimeInterval = 0

    // Animated jump state.
    private var jumpFrom: CGFloat = 0
    private var jumpTo: CGFloat = 0
    private var jumpStart: CFTimeInterval = 0
    private var jumpDuration: CFTimeInterval = 0.35
    private var isJumping = false

    func play() {
        if offset >= maxOffset && maxOffset > 0 { offset = 0 }
        isPlaying = true
        startLinkIfNeeded()
        setIdleTimerDisabled(true)
    }

    func pause() {
        isPlaying = false
        if !isJumping { stopLink() }
        setIdleTimerDisabled(false)
    }

    /// Smoothly scrolls to `target`. Keeps playing if it was playing.
    func jump(to target: CGFloat) {
        jumpFrom = offset
        jumpTo = min(max(0, target), maxOffset)
        jumpStart = 0
        isJumping = true
        startLinkIfNeeded()
    }

    private func startLinkIfNeeded() {
        guard link == nil else { return }
        lastTimestamp = 0
        let newLink = CADisplayLink(target: self, selector: #selector(step(_:)))
        newLink.add(to: .main, forMode: .common)
        link = newLink
    }

    private func stopLink() {
        link?.invalidate()
        link = nil
    }

    /// UIApplication is main-actor isolated. The display link runs on the main
    /// thread, but that callback is not a MainActor job, so hop explicitly.
    private func setIdleTimerDisabled(_ disabled: Bool) {
        Task { @MainActor in
            UIApplication.shared.isIdleTimerDisabled = disabled
        }
    }

    func reset() {
        pause()
        isJumping = false
        stopLink()
        offset = 0
    }

    func nudge(by delta: CGFloat) {
        offset = min(max(0, offset + delta), maxOffset)
    }

    @objc private func step(_ displayLink: CADisplayLink) {
        let now = displayLink.timestamp
        if isJumping {
            if jumpStart == 0 { jumpStart = now }
            let t = min(1, (now - jumpStart) / jumpDuration)
            let eased = t < 0.5 ? 2 * t * t : 1 - pow(-2 * t + 2, 2) / 2
            offset = jumpFrom + (jumpTo - jumpFrom) * CGFloat(eased)
            lastTimestamp = now
            if t >= 1 {
                isJumping = false
                if !isPlaying { stopLink() }
            }
            return
        }
        guard isPlaying else { stopLink(); return }
        if lastTimestamp == 0 {
            lastTimestamp = now
            return
        }
        let dt = now - lastTimestamp
        lastTimestamp = now
        let next = offset + CGFloat(speed * dt)
        if next >= maxOffset {
            offset = maxOffset
            pause()
        } else {
            offset = next
        }
    }

    deinit {
        link?.invalidate()
    }
}
