import Foundation
import Observation
import VaasiCore

/// Live microphone meter for Settings and calibration: same capture, gain and
/// speech detection as a real session.
@MainActor @Observable
final class MicTester {
    private(set) var level: Double = 0
    private(set) var isSpeaking = false
    private(set) var error: String?
    private(set) var inputName = ""

    @ObservationIgnored private var source: MicrophoneSource?
    @ObservationIgnored private let meter = LevelMeter()
    @ObservationIgnored private var timer: Timer?
    @ObservationIgnored private var vad = VoiceActivityDetector()
    @ObservationIgnored private var gain = AutoGain()

    func start(device: AudioInputDevice?, preferences: Preferences) {
        stop()
        guard let device else {
            error = AudioInputError.noInputDevice.localizedDescription
            return
        }
        error = nil
        inputName = device.name
        let source = MicrophoneSource(device: device, noiseSuppression: preferences.noiseSuppression)
        self.source = source
        let sink = AudioSink(meter: meter, onBuffer: nil)
        Task {
            do { try await source.start(sink: sink) } catch { self.error = error.localizedDescription }
        }
        vad = VoiceActivityDetector(sensitivity: preferences.sensitivity)
        gain = AutoGain()
        timer = Timer.scheduledTimer(withTimeInterval: 1 / 30, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick(preferences: preferences) }
        }
    }

    private func tick(preferences: Preferences) {
        guard let raw = meter.take() else { return }
        let db = preferences.autoGain ? gain.apply(levelDB: raw, dt: 1 / 30) : raw
        vad.sensitivity = preferences.sensitivity
        isSpeaking = vad.process(levelDB: db, dt: 1 / 30)
        let target = AudioLevel.normalized(db: db)
        level += (target - level) * (target > level ? 0.6 : 0.2)
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        source?.stop()
        source = nil
        level = 0
        isSpeaking = false
    }
}
