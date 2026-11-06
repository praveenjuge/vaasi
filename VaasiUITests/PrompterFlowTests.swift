import XCTest

final class PrompterFlowTests: VaasiUITestCase {
    func testNotchPrompterIsPrivateAndScrolls() {
        launch()
        select(note: "Welcome")
        moveMouseAway()
        startPrompter()
        let running = waitForState("running") { $0["phase"] == "running" }
        XCTAssertEqual(running["placement"], "notch")
        XCTAssertEqual(running["allSpaces"], "1", "Visible on every Space")
        XCTAssertEqual(running["mainVisible"], "0", "Library hides while presenting")

        // Notch prompter hugs the top of the screen.
        let frame = prompterWindow.frame
        XCTAssertLessThan(frame.minY, 2, "Prompter starts at the top edge")

        let start = number("offset")
        sleep(2)
        XCTAssertGreaterThan(number("offset"), start + 30, "Continuous mode scrolls")
        attachScreenshot("notch-running")
    }

    func testCountdownBeforeStart() {
        launch(defaults: ["countdownSeconds": "3"])
        select(note: "Welcome")
        moveMouseAway()
        startPrompter()
        waitForState("countdown") { $0["phase"]?.hasPrefix("countdown") == true }
        XCTAssertTrue(app.staticTexts["prompter.countdown"].exists)
        attachScreenshot("countdown")
        XCTAssertEqual(number("offset"), 0, "No scrolling during the countdown")
        waitForState("running after countdown", timeout: 6) { $0["phase"] == "running" }
    }

    func testHoverPausesAndPauseButtonHolds() {
        launch()
        select(note: "Welcome")
        moveMouseAway()
        startPrompter()
        waitForState("scrolling") { Double($0["offset"] ?? "0") ?? 0 > 10 }

        prompterWindow.hover()
        let hovered = waitForState("hover pause") { $0["hover"] == "1" }
        let held = Double(hovered["offset"] ?? "0") ?? 0
        sleep(1.5)
        XCTAssertLessThanOrEqual(number("offset"), held + 3, "Hovering pauses")

        let pause = app.buttons["prompter.pause"]
        XCTAssertTrue(pause.waitForExistence(timeout: 3))
        pause.click()
        waitForState("paused") { $0["paused"] == "1" }
        moveMouseAway()
        let pausedAt = number("offset")
        sleep(1.5)
        XCTAssertEqual(number("offset"), pausedAt, "Pause holds after the pointer leaves")

        app.typeKey(.space, modifierFlags: [.option, .shift])
        waitForState("resumed by shortcut") { $0["paused"] == "0" }
        sleep(1)
        XCTAssertGreaterThan(number("offset"), pausedAt)
    }

    func testSpeedShortcutsStepAndClamp() {
        launch()
        select(note: "Welcome")
        moveMouseAway()
        startPrompter()
        waitForState("running") { $0["phase"] == "running" }
        XCTAssertEqual(state()["speed"], "30")
        app.typeKey(.rightArrow, modifierFlags: .shift)
        waitForState("faster") { $0["speed"] == "36" }
        for _ in 0..<20 { app.typeKey(.leftArrow, modifierFlags: .shift) }
        waitForState("slowest step") { $0["speed"] == "4" }
    }

    func testLineStepShortcutsMoveTheText() {
        launch(defaults: ["scrollMode": "voice"], audio: "silence:60")
        select(note: "Welcome")
        moveMouseAway()
        startPrompter()
        waitForState("running") { $0["phase"] == "running" }
        XCTAssertEqual(number("offset"), 0)
        app.typeKey(.downArrow, modifierFlags: .shift)
        let moved = waitForState("forward a line") { Double($0["offset"] ?? "0") ?? 0 > 10 }
        app.typeKey(.upArrow, modifierFlags: .shift)
        waitForState("back a line") { (Double($0["offset"] ?? "0") ?? 0) < (Double(moved["offset"] ?? "0") ?? 0) }
    }

    func testCuesJumpBetweenSections() {
        launch(defaults: ["scrollMode": "voice"], audio: "silence:60")
        select(note: "Using cues")
        moveMouseAway()
        startPrompter()
        waitForState("first cue") { $0["section"] == "1/4" }
        let next = app.buttons["cue.next"]
        XCTAssertTrue(next.waitForExistence(timeout: 5))
        next.click()
        waitForState("second cue") { $0["section"] == "2/4" }
        app.typeKey(.downArrow, modifierFlags: [.option, .shift])
        waitForState("third cue by shortcut") { $0["section"] == "3/4" }

        let menu = app.descendants(matching: .any)["cue.menu"].firstMatch
        menu.click()
        let item = app.menuItems["4  Moving between sections"]
        XCTAssertTrue(item.waitForExistence(timeout: 5))
        attachScreenshot("cue-menu")
        item.click()
        waitForState("jumped to last cue") { $0["section"] == "4/4" }
        app.buttons["cue.previous"].click()
        waitForState("back one cue") { $0["section"] == "3/4" }
    }

    func testStopRestoresTheLibrary() {
        launch()
        select(note: "Welcome")
        startPrompter()
        waitForState("running") { $0["phase"] == "running" }
        prompterWindow.hover()
        let stop = app.buttons["prompter.stop"]
        XCTAssertTrue(stop.waitForExistence(timeout: 5))
        stop.click()
        let gone = NSPredicate(format: "exists == false")
        expectation(for: gone, evaluatedWith: stateElement)
        waitForExpectations(timeout: 5)
        XCTAssertTrue(libraryWindow.isHittable, "Library comes back after stopping")
    }

    func testFloatingWindowCanMoveAndReturnToNotch() {
        launch()
        select(note: "Welcome")
        startPrompter()
        waitForState("running") { $0["phase"] == "running" }
        prompterWindow.hover()
        app.buttons["prompter.placement"].click()
        waitForState("floating") { $0["placement"] == "floating" }
        let before = prompterWindow.frame
        XCTAssertGreaterThan(before.minY, 20, "Floating window sits below the menu bar")
        attachScreenshot("floating")

        // Drag it somewhere else by its background.
        let start = prompterWindow.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        start.press(forDuration: 0.2, thenDragTo: start.withOffset(CGVector(dx: -160, dy: 120)))
        let after = prompterWindow.frame
        XCTAssertNotEqual(before.origin, after.origin, "Floating prompter moves")

        prompterWindow.hover()
        app.buttons["prompter.placement"].click()
        waitForState("back in the notch") { $0["placement"] == "notch" }
    }

    func testDraggingTheEdgeResizesTheNotchPrompter() {
        launch()
        select(note: "Welcome")
        startPrompter()
        waitForState("running") { $0["phase"] == "running" }
        let before = prompterWindow.frame
        let handle = app.descendants(matching: .any)["prompter.resize.right"].firstMatch
        let grip = handle.exists ? handle.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
            : prompterWindow.coordinate(withNormalizedOffset: CGVector(dx: 0, dy: 0)).withOffset(CGVector(dx: before.width - 4, dy: 60))
        grip.press(forDuration: 0.2, thenDragTo: grip.withOffset(CGVector(dx: 60, dy: 0)))
        let wider = prompterWindow.frame
        XCTAssertGreaterThan(wider.width, before.width + 60, "Dragging the side widens both sides")
        XCTAssertEqual(wider.midX, before.midX, accuracy: 2, "Stays centered on the notch")
    }

    func testEndOfScriptIsReached() {
        launch(defaults: ["speedIndex": "14"])
        select(note: "Using cues")
        moveMouseAway()
        startPrompter()
        waitForState("end of script", timeout: 30) { $0["end"] == "1" }
        attachScreenshot("end")
    }
}
