import Foundation
import UIKit
import QuartzCore
import Combine

/// Drives smooth scrolling with a CADisplayLink (one step per screen refresh).
final class ScrollEngine: NSObject, ObservableObject {
    @Published var offset: CGFloat = 0
    @Published private(set) var isPlaying: Bool = false

    /// Points per second.
    var speed: Double = 60
    var maxOffset: CGFloat = 0

    private var link: CADisplayLink?
    private var lastTimestamp: CFTimeInterval = 0

    func play() {
        guard link == nil else { return }
        if offset >= maxOffset && maxOffset > 0 { offset = 0 }
        lastTimestamp = 0
        let newLink = CADisplayLink(target: self, selector: #selector(step(_:)))
        newLink.add(to: .main, forMode: .common)
        link = newLink
        isPlaying = true
        UIApplication.shared.isIdleTimerDisabled = true
    }

    func pause() {
        link?.invalidate()
        link = nil
        isPlaying = false
        UIApplication.shared.isIdleTimerDisabled = false
    }

    func reset() {
        pause()
        offset = 0
    }

    func nudge(by delta: CGFloat) {
        offset = min(max(0, offset + delta), maxOffset)
    }

    @objc private func step(_ displayLink: CADisplayLink) {
        if lastTimestamp == 0 {
            lastTimestamp = displayLink.timestamp
            return
        }
        let dt = displayLink.timestamp - lastTimestamp
        lastTimestamp = displayLink.timestamp
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
