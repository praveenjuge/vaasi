import Foundation

/// Turns a stream of input levels into "speaking" / "quiet", with hysteresis so
/// short gaps between words don't stop the prompter.
public struct VoiceActivityDetector: Equatable, Sendable {
    /// 0 (needs loud speech) … 1 (picks up whispers).
    public var sensitivity: Double {
        didSet { sensitivity = min(1, max(0, sensitivity)) }
    }
    public var attack: Double = 0.08
    public var release: Double = 0.7

    public private(set) var isSpeaking = false
    /// Estimated background level. Speech must rise clearly above it.
    public private(set) var noiseFloorDB: Double = -70
    private var aboveFor: Double = 0
    private var belowFor: Double = 0

    public init(sensitivity: Double = 0.6) {
        self.sensitivity = min(1, max(0, sensitivity))
    }

    /// Absolute level (dBFS) speech must reach.
    public var thresholdDB: Double { -20 - sensitivity * 40 }

    /// The level that counts as speech right now: above the absolute threshold
    /// and above the background noise.
    public var effectiveThresholdDB: Double {
        max(thresholdDB, noiseFloorDB + 6 + (1 - sensitivity) * 10)
    }

    @discardableResult
    public mutating func process(levelDB: Double, dt: Double) -> Bool {
        // Noise floor falls quickly to quiet input and creeps up slowly, so
        // speech bursts barely move it but a steady fan or hum does.
        if levelDB < noiseFloorDB {
            noiseFloorDB += (levelDB - noiseFloorDB) * min(1, dt / 0.3)
        } else {
            noiseFloorDB = min(levelDB, noiseFloorDB + 1.5 * dt)
        }

        if levelDB >= effectiveThresholdDB {
            aboveFor += dt
            belowFor = 0
            if aboveFor >= attack { isSpeaking = true }
        } else {
            belowFor += dt
            aboveFor = 0
            if belowFor >= release { isSpeaking = false }
        }
        return isSpeaking
    }

    public mutating func reset() {
        isSpeaking = false
        noiseFloorDB = -70
        aboveFor = 0
        belowFor = 0
    }
}

public enum AudioLevel {
    /// Maps dBFS to 0…1 for meters and the voice beam.
    public static func normalized(db: Double) -> Double {
        min(1, max(0, (db + 60) / 50))
    }

    /// RMS of float samples in dBFS (floor −120).
    public static func rmsDB(_ samples: UnsafeBufferPointer<Float>) -> Double {
        guard !samples.isEmpty else { return -120 }
        var sum: Float = 0
        for sample in samples { sum += sample * sample }
        let rms = sqrt(sum / Float(samples.count))
        return rms > 0 ? max(-120, Double(20 * log10(rms))) : -120
    }
}

/// Automatic gain: tracks recent peak speech level and lifts quiet microphones
/// toward a target, so the detector and beam behave the same on every input.
public struct AutoGain: Equatable, Sendable {
    public var targetPeakDB: Double = -18
    public var maxBoostDB: Double = 24
    private var peakDB: Double = -40

    public init() {}

    public mutating func apply(levelDB: Double, dt: Double) -> Double {
        if levelDB > peakDB {
            peakDB = levelDB
        } else {
            // Peak decays ~3 dB per second so the gain adapts when you move
            // away, but never below -45 dB, which caps the boost in silence.
            peakDB = max(-45, peakDB - 3 * dt)
        }
        let boost = min(maxBoostDB, max(0, targetPeakDB - peakDB))
        return levelDB + boost
    }
}
