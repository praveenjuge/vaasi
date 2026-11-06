import Testing
@testable import VaasiCore

@Suite("Voice activity")
struct VoiceActivityTests {
    private func feed(_ detector: inout VoiceActivityDetector, db: Double, seconds: Double) -> Bool {
        let dt = 0.02
        var speaking = detector.isSpeaking
        for _ in 0..<Int(seconds / dt) { speaking = detector.process(levelDB: db, dt: dt) }
        return speaking
    }

    @Test func detectsSpeechAndSilenceWithHysteresis() {
        var vad = VoiceActivityDetector(sensitivity: 0.6)
        #expect(!feed(&vad, db: -70, seconds: 1))
        #expect(feed(&vad, db: -25, seconds: 0.2))
        // A short gap between words keeps speaking.
        #expect(feed(&vad, db: -70, seconds: 0.3))
        #expect(!feed(&vad, db: -70, seconds: 1))
    }

    @Test func sensitivityMovesThreshold() {
        #expect(VoiceActivityDetector(sensitivity: 1).thresholdDB < VoiceActivityDetector(sensitivity: 0).thresholdDB)
        var quiet = VoiceActivityDetector(sensitivity: 0.1)
        #expect(!feed(&quiet, db: -40, seconds: 0.5))
        var keen = VoiceActivityDetector(sensitivity: 0.9)
        #expect(feed(&keen, db: -40, seconds: 0.5))
    }

    @Test func steadyNoiseIsIgnored() {
        var vad = VoiceActivityDetector(sensitivity: 0.9)
        // A fan at -45 dB: it trips the absolute threshold at first, but the
        // noise floor catches up and it stops counting as speech.
        _ = feed(&vad, db: -45, seconds: 30)
        #expect(!feed(&vad, db: -45, seconds: 1))
        // Real speech well above the fan still counts.
        #expect(feed(&vad, db: -22, seconds: 0.3))
    }

    @Test func autoGainLiftsQuietInputButCapsBoost() {
        var gain = AutoGain()
        var out = 0.0
        for _ in 0..<100 { out = gain.apply(levelDB: -40, dt: 0.02) }
        #expect(out > -40)
        #expect(out <= -40 + gain.maxBoostDB)
        var loud = AutoGain()
        #expect(loud.apply(levelDB: -10, dt: 0.02) == -10)
    }

    @Test func levelNormalization() {
        #expect(AudioLevel.normalized(db: -120) == 0)
        #expect(AudioLevel.normalized(db: 0) == 1)
        let samples: [Float] = Array(repeating: 0.5, count: 64)
        let db = samples.withUnsafeBufferPointer { AudioLevel.rmsDB($0) }
        #expect(abs(db - (-6.02)) < 0.1)
    }
}
