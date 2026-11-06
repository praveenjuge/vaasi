import AVFoundation
import Foundation
import Testing
import VaasiCore
@testable import Vaasi

@Suite("Voice pipeline", .serialized)
@MainActor
struct VoicePipelineTests {
    let script = "Thank you for listening today. We built this tool so you can keep eye contact while you speak. The words scroll as you talk and wait when you stop."

    /// Real path: synthesized speech → audio sink → on-device recognizer →
    /// transcript → script follower.
    @Test(.timeLimit(.minutes(2)))
    func recognizerFollowsSpokenScript() async throws {
        let session = SpeechSession()
        var follower = ScriptFollower(text: script)
        var best = -1
        session.onWords = { words in
            follower.update(transcriptWords: words)
            best = max(best, follower.lastMatchedIndex)
        }
        let feeder = try await session.start(localeIdentifier: "en-US")
        let meter = LevelMeter()
        var loudest = -120.0
        let source = SynthesizedSource(spec: "speak:\(script)|silence:2")
        try await source.start(sink: AudioSink(meter: meter, onBuffer: { feeder.feed($0) }))

        let deadline = Date().addingTimeInterval(60)
        while Date() < deadline, best < follower.tokens.count - 4 {
            if let db = meter.take() { loudest = max(loudest, db) }
            try await Task.sleep(for: .milliseconds(100))
        }
        source.stop()
        session.stop()

        #expect(loudest > -40, "Synthesized speech reaches the level meter")
        #expect(best >= follower.tokens.count - 4, "Follower reached the end (\(best)/\(follower.tokens.count))")
    }

    @Test func supportedLocalesIncludeEnglish() async {
        let locales = await SpeechSession.supportedLocales()
        #expect(locales.contains { $0.identifier.hasPrefix("en") })
    }

    @Test func microphoneChoiceFallsBackWhenUnplugged() {
        let devices = AudioDevices()
        guard let first = devices.inputs.first else { return }
        #expect(devices.resolve(uid: first.uid) == first, "A plugged-in choice is used")
        let fallback = devices.resolve(uid: "missing-device-uid")
        #expect(fallback != nil, "An unplugged choice falls back to an available input")
        #expect(devices.inputs.contains { $0 == fallback })
    }
}
