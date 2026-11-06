import XCTest

/// Launches the real app in test mode and reads the prompter's live state.
@MainActor
class VaasiUITestCase: XCTestCase {
    var app: XCUIApplication!

    override func setUp() async throws {
        continueAfterFailure = false
    }

    override func tearDown() async throws {
        if let app, app.state != .notRunning {
            attachScreenshot("final")
            app.terminate()
        }
    }

    /// `defaults` are written to the argument domain, so they override stored
    /// preferences for this run only.
    @discardableResult
    func launch(defaults: [String: String] = [:], audio: String? = nil, extraArguments: [String] = [],
                allowCapture: Bool = true, presentLibrary: Bool = true) -> XCUIApplication {
        let app = XCUIApplication()
        var settings = ["countdownSeconds": "0", "scrollMode": "continuous", "adaptiveTempo": "NO"]
        settings.merge(defaults) { $1 }
        app.launchArguments = ["-UITesting"] + (allowCapture ? ["-AllowCapture"] : []) + extraArguments
            + settings.flatMap { ["-\($0.key)", $0.value] }
        if let audio { app.launchEnvironment["VAASI_SYNTH_AUDIO"] = audio }
        app.launch()
        app.activate()
        self.app = app
        guard presentLibrary else { return app }
        let library = app.outlines["library.list"]
        if !library.waitForExistence(timeout: 3) {
            // Under the test launcher SwiftUI holds the first window offscreen;
            // ordering it from the Window menu presents it right away.
            app.menuBars.menuBarItems["Window"].menus.menuItems["Vaasi"].click()
        }
        XCTAssertTrue(library.waitForExistence(timeout: 10), "Library window should open")
        return app
    }

    // MARK: Notes

    var libraryWindow: XCUIElement {
        app.windows.containing(.outline, identifier: "library.list").firstMatch
    }

    func noteRow(_ title: String) -> XCUIElement {
        // Row titles are exposed as the text's value, not its label.
        app.outlines["library.list"].staticTexts.matching(NSPredicate(format: "value == %@", title)).firstMatch
    }

    func select(note title: String) {
        let row = noteRow(title)
        XCTAssertTrue(row.waitForExistence(timeout: 5), "Note “\(title)” should be listed")
        row.click()
    }

    // MARK: Prompter

    var stateElement: XCUIElement { app.descendants(matching: .any)["prompter.state"] }

    func state() -> [String: String] {
        guard stateElement.exists, let value = stateElement.value as? String else { return [:] }
        return Dictionary(uniqueKeysWithValues: value.split(separator: ";").compactMap { pair in
            let parts = pair.split(separator: "=", maxSplits: 1).map(String.init)
            return parts.count == 2 ? (parts[0], parts[1]) : nil
        })
    }

    func number(_ key: String) -> Double { Double(state()[key] ?? "") ?? .nan }

    func startPrompter() {
        app.typeKey(.return, modifierFlags: .command)
        XCTAssertTrue(stateElement.waitForExistence(timeout: 10), "Prompter should appear")
    }

    /// Waits until the prompter state satisfies `condition`.
    @discardableResult
    func waitForState(_ description: String, timeout: TimeInterval = 10,
                      _ condition: @escaping ([String: String]) -> Bool) -> [String: String] {
        let deadline = Date().addingTimeInterval(timeout)
        var last: [String: String] = [:]
        while Date() < deadline {
            last = state()
            if condition(last) { return last }
            RunLoop.current.run(until: Date().addingTimeInterval(0.1))
        }
        XCTFail("Timed out waiting for \(description). Last state: \(last)")
        return last
    }

    func sleep(_ seconds: TimeInterval) {
        RunLoop.current.run(until: Date().addingTimeInterval(seconds))
    }

    func attachScreenshot(_ label: String) {
        let shot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        shot.name = label
        shot.lifetime = .keepAlways
        add(shot)
    }

    /// Moves the pointer away from the prompter so hover-pause doesn't interfere.
    func moveMouseAway() {
        // Hover just below the prompter panel, whose frame is the one element
        // that stays valid while presenting. The library and app elements can
        // report garbage frames on macOS 27, which sends the hover to infinity
        // and aborts the test. Before the prompter starts, the pointer rests on
        // the clicked note row — nowhere near the panel — so doing nothing is
        // already safe.
        let panel = app.descendants(matching: .any)["prompter.window"].firstMatch
        guard panel.exists, panel.isHittable else { return }
        let frame = panel.frame
        guard frame.origin.x.isFinite, frame.origin.y.isFinite,
              frame.width.isFinite, frame.height.isFinite, frame.width > 0, frame.height > 0 else { return }
        panel.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 1.0))
            .withOffset(CGVector(dx: 0, dy: 300)).hover()
    }

    /// The prompter panel. macOS 27 keeps nonactivating panels out of the app's
    /// window list, so fall back to the prompter's root element.
    var prompterWindow: XCUIElement {
        let window = app.windows.containing(.any, identifier: "prompter.state").firstMatch
        if window.exists { return window }
        return app.descendants(matching: .any)["prompter.window"].firstMatch
    }
}
