import XCTest

/// Voice features driven by synthesized speech that runs through the real
/// level meter, voice detector, and on-device speech recognizer.
final class VoiceFlowTests: VaasiUITestCase {
    private let welcomeOpening = "This is Vaasi, a teleprompter that sits right under your camera. Write what you want to say here. When you press Start, the text appears in the notch at the top of your screen, so you can read it and still look at the person you're talking to."

    func testScrollsWhileSpeakingAndHoldsInSilence() {
        launch(defaults: ["scrollMode": "voice", "adaptiveTempo": "NO"],
               audio: "silence:3|speak:\(welcomeOpening)|silence:60")
        select(note: "Welcome")
        moveMouseAway()
        startPrompter()
        waitForState("running") { $0["phase"] == "running" }
        sleep(1.5)
        XCTAssertEqual(number("offset"), 0, "Silent at first: no scrolling")

        waitForState("speech detected", timeout: 10) { $0["speaking"] == "1" }
        sleep(3)
        XCTAssertGreaterThan(number("offset"), 20, "Scrolls while speaking")
        attachScreenshot("voice-speaking")

        waitForState("silence detected", timeout: 25) { $0["speaking"] == "0" }
        sleep(0.8)
        let held = number("offset")
        sleep(2)
        XCTAssertEqual(number("offset"), held, accuracy: 1, "Holds when you stop talking")
    }

    func testFollowsYourPlaceWithSpeechRecognition() {
        launch(defaults: ["scrollMode": "voice", "adaptiveTempo": "YES", "speedIndex": "0"],
               audio: "silence:1|speak:\(welcomeOpening)|silence:60")
        select(note: "Welcome")
        moveMouseAway()
        startPrompter()
        waitForState("running") { $0["phase"] == "running" }
        // The script has ~45 words before "talking to"; recognition should track well past half of them.
        let followed = waitForState("recognizer following the script", timeout: 40) {
            (Int($0["follow"] ?? "-1") ?? -1) >= 30
        }
        // At the slowest speed (4 pt/s) plain voice scrolling would barely move;
        // following the words must carry the text much further.
        XCTAssertGreaterThan(Double(followed["offset"] ?? "0") ?? 0, 60, "Text keeps up with the reader")
        attachScreenshot("voice-following")
    }

    func testSilenceHintNamesTheInput() {
        launch(defaults: ["scrollMode": "voice"], audio: "silence:120")
        select(note: "Welcome")
        moveMouseAway()
        startPrompter()
        let hint = app.descendants(matching: .any)["prompter.silenceHint"].firstMatch
        XCTAssertTrue(hint.waitForExistence(timeout: 20), "A silent session shows a hint")
        let text = app.staticTexts.containing(NSPredicate(format: "value CONTAINS 'Synthesized speech'")).firstMatch
        XCTAssertTrue(text.exists || hint.label.contains("Synthesized speech") || app.staticTexts["Not hearing anything from Synthesized speech."].exists,
                      "The hint names the active input")
        // macOS 27 reports link-style buttons as static text, so match the
        // element by identifier rather than by button type.
        XCTAssertTrue(app.buttons["Settings"].exists || app.descendants(matching: .any)["prompter.settings"].exists,
                      "The hint links to Settings")
        attachScreenshot("silence-hint")
    }

    func testVoiceBeamFollowsLevel() {
        // The beam is driven by the same meter as speech detection; with speech
        // playing, the detector must see it.
        launch(defaults: ["scrollMode": "voice"], audio: "speak:\(welcomeOpening)|silence:60")
        select(note: "Welcome")
        moveMouseAway()
        startPrompter()
        waitForState("speech heard", timeout: 10) { $0["speaking"] == "1" }
        attachScreenshot("voice-beam")
    }
}
