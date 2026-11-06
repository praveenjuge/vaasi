import Testing
@testable import VaasiCore

@Suite("Scroll engine")
struct ScrollEngineTests {
    private func run(_ engine: inout ScrollEngine, seconds: Double, speaking: Bool) {
        let dt = 1.0 / 60
        for _ in 0..<Int(seconds * 60) { engine.tick(dt: dt, isSpeaking: speaking) }
    }

    @Test func continuousModeScrollsAtSpeed() {
        var engine = ScrollEngine(mode: .continuous, speedIndex: 6)
        engine.maxOffset = 10_000
        run(&engine, seconds: 3, speaking: false)
        // ~3 s at 30 pt/s minus the ease-in.
        #expect(engine.offset > 80 && engine.offset < 92)
    }

    @Test func voiceModeOnlyMovesWhileSpeaking() {
        var engine = ScrollEngine(mode: .voice)
        engine.maxOffset = 10_000
        run(&engine, seconds: 2, speaking: false)
        #expect(engine.offset == 0)
        run(&engine, seconds: 2, speaking: true)
        let afterSpeech = engine.offset
        #expect(afterSpeech > 40)
        run(&engine, seconds: 2, speaking: false)
        // Eases out, then holds.
        #expect(engine.offset - afterSpeech < 10)
        let held = engine.offset
        run(&engine, seconds: 2, speaking: false)
        #expect(engine.offset == held)
    }

    @Test func pauseAndHoverHaltImmediately() {
        var engine = ScrollEngine(mode: .continuous)
        engine.maxOffset = 10_000
        run(&engine, seconds: 1, speaking: false)
        engine.isHoverPaused = true
        let at = engine.offset
        run(&engine, seconds: 1, speaking: false)
        #expect(engine.offset == at)
        engine.isHoverPaused = false
        engine.isPaused = true
        run(&engine, seconds: 1, speaking: false)
        #expect(engine.offset == at)
    }

    @Test func speedIsSteppedAndClamped() {
        var engine = ScrollEngine(speedIndex: 0)
        #expect(engine.speed == 4)
        engine.slower()
        #expect(engine.speed == 4)
        for _ in 0..<50 { engine.faster() }
        #expect(engine.speed == ScrollEngine.speedSteps.last)
        #expect(ScrollEngine.speedSteps == ScrollEngine.speedSteps.sorted())
    }

    @Test func stopsAtEnd() {
        var engine = ScrollEngine(mode: .continuous, speedIndex: 14)
        engine.maxOffset = 100
        run(&engine, seconds: 5, speaking: false)
        #expect(engine.offset == 100)
        #expect(engine.isAtEnd)
    }

    @Test func followTargetCatchesUpAndWaits() {
        var engine = ScrollEngine(mode: .voice)
        engine.maxOffset = 10_000
        engine.followTarget = 300
        run(&engine, seconds: 3, speaking: true)
        #expect(engine.offset > 250)
        // Reader is far behind the view: hold even while speaking.
        engine.setOffset(600)
        engine.followTarget = 500
        run(&engine, seconds: 1, speaking: true)
        #expect(engine.offset < 601)
    }
}
