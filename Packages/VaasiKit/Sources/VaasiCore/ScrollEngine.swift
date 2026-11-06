import Foundation

/// How the prompter decides when to move.
public enum ScrollMode: String, Codable, CaseIterable, Sendable, Identifiable {
    /// Scroll while you speak, hold while you're quiet.
    case voice
    /// Scroll at a constant speed.
    case continuous

    public var id: String { rawValue }
}

/// Pure scrolling model. The app calls `tick` once per display frame.
public struct ScrollEngine: Equatable, Sendable {
    /// Stepped speeds in points per second, slowest first.
    public static let speedSteps: [Double] = [4, 8, 12, 16, 20, 25, 30, 36, 42, 50, 60, 72, 86, 100, 120]
    public static let defaultSpeedIndex = 6

    public var mode: ScrollMode
    public private(set) var speedIndex: Int
    public private(set) var offset: Double = 0
    public var maxOffset: Double = 0

    /// Paused from the pause button, a shortcut, or the remote.
    public var isPaused = false
    /// Paused because the pointer is over the prompter.
    public var isHoverPaused = false
    /// When adaptive tempo is on: where the last spoken word wants the view to be.
    public var followTarget: Double?

    /// 0…1, eases in and out so voice starts and stops feel smooth.
    public private(set) var momentum: Double = 0

    public init(mode: ScrollMode = .voice, speedIndex: Int = ScrollEngine.defaultSpeedIndex) {
        self.mode = mode
        self.speedIndex = ScrollEngine.clampedSpeedIndex(speedIndex)
    }

    public var speed: Double { ScrollEngine.speedSteps[speedIndex] }
    public var isAtEnd: Bool { maxOffset > 0 && offset >= maxOffset - 0.5 }
    public var isHalted: Bool { isPaused || isHoverPaused }
    public var progress: Double { maxOffset > 0 ? min(1, offset / maxOffset) : 0 }

    public static func clampedSpeedIndex(_ index: Int) -> Int {
        min(max(index, 0), speedSteps.count - 1)
    }

    public mutating func faster() { speedIndex = ScrollEngine.clampedSpeedIndex(speedIndex + 1) }
    public mutating func slower() { speedIndex = ScrollEngine.clampedSpeedIndex(speedIndex - 1) }
    public mutating func setSpeedIndex(_ index: Int) { speedIndex = ScrollEngine.clampedSpeedIndex(index) }

    /// Jumps (manual scrolling, cue jumps, line steps). Clears any pending follow target behind it.
    public mutating func setOffset(_ value: Double) {
        offset = min(max(0, value), maxOffset)
        if let target = followTarget, target < offset { followTarget = nil }
    }

    public mutating func nudge(by delta: Double) { setOffset(offset + delta) }

    /// Advances the model by `dt` seconds.
    public mutating func tick(dt: Double, isSpeaking: Bool) {
        guard dt > 0 else { return }
        let wantsToMove: Bool
        switch mode {
        case .continuous: wantsToMove = !isHalted
        case .voice: wantsToMove = !isHalted && (isSpeaking || hasFollowLead)
        }

        // Ease momentum: ~0.25 s to start, ~0.35 s to stop.
        let rate = wantsToMove ? dt / 0.25 : -dt / 0.35
        momentum = min(1, max(0, momentum + rate))
        if isHalted { momentum = 0 }
        guard momentum > 0 else { return }

        var velocity = speed
        if mode == .voice, let target = followTarget {
            let lead = target - offset
            if lead > 0 {
                // Catch up with the reader: faster the further behind we are.
                velocity = max(speed, lead * 1.6)
            } else if lead < -40 {
                // Ahead of the reader by more than a line: wait for them.
                velocity = 0
            } else {
                velocity = speed * 0.6
            }
        }
        offset = min(maxOffset, offset + velocity * momentum * dt)
    }

    private var hasFollowLead: Bool {
        guard let target = followTarget else { return false }
        return target - offset > 2
    }
}
