import XCTest

final class LibraryFlowTests: VaasiUITestCase {
    func testStarterNotesAndWritingANewNote() {
        launch()
        XCTAssertTrue(noteRow("Welcome").waitForExistence(timeout: 5))
        XCTAssertTrue(noteRow("Using cues").exists)

        app.typeKey("n", modifierFlags: .command)
        let title = app.textFields["editor.title"]
        XCTAssertTrue(title.waitForExistence(timeout: 5))
        title.click()
        title.typeText("Quarterly update")
        let body = app.textViews["editor.body"]
        body.click()
        body.typeText("Revenue grew this quarter.\n---\nNext steps for the team.")

        XCTAssertTrue(noteRow("Quarterly update").waitForExistence(timeout: 5))
        XCTAssertEqual(body.value as? String, "Revenue grew this quarter.\n---\nNext steps for the team.")
        attachScreenshot("new-note")
    }

    func testSearchFindsTextAcrossAllNotes() {
        launch()
        XCTAssertTrue(noteRow("Welcome").waitForExistence(timeout: 5))
        app.typeKey("f", modifierFlags: .command)
        app.typeText("three dashes")
        XCTAssertTrue(noteRow("Using cues").waitForExistence(timeout: 5))
        let gone = NSPredicate(format: "exists == false")
        expectation(for: gone, evaluatedWith: noteRow("Welcome"))
        waitForExpectations(timeout: 5)
        attachScreenshot("search")
    }

    func testInsertDividerFromContextMenu() {
        launch()
        app.typeKey("n", modifierFlags: .command)
        let body = app.textViews["editor.body"]
        XCTAssertTrue(body.waitForExistence(timeout: 5))
        body.click()
        body.typeText("First part")
        body.rightClick()
        let item = app.menuItems["Insert Divider"]
        XCTAssertTrue(item.waitForExistence(timeout: 5))
        item.click()
        body.typeText("Second part")
        XCTAssertEqual(body.value as? String, "First part\n---\nSecond part")
    }

    func testDeletingANoteAsksFirst() {
        launch()
        let row = noteRow("Using cues")
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        row.rightClick()
        app.menuItems["Delete…"].click()
        let cancel = app.buttons["Cancel"]
        XCTAssertTrue(cancel.waitForExistence(timeout: 5), "Should ask before deleting")
        cancel.click()
        XCTAssertTrue(row.exists, "Cancel keeps the note")

        row.rightClick()
        app.menuItems["Delete…"].click()
        let delete = app.sheets.buttons["Delete"].exists ? app.sheets.buttons["Delete"] : app.buttons["Delete"].firstMatch
        XCTAssertTrue(delete.waitForExistence(timeout: 5))
        delete.click()
        let gone = NSPredicate(format: "exists == false")
        expectation(for: gone, evaluatedWith: row)
        waitForExpectations(timeout: 5)
    }

    func testFirstRunCalibrationWindow() {
        launch(extraArguments: ["-ShowOnboarding"])
        let done = app.buttons["calibration.done"]
        XCTAssertTrue(done.waitForExistence(timeout: 10), "Calibration window should open on first run")
        XCTAssertTrue(app.staticTexts["Set up your voice"].exists)
        XCTAssertTrue(app.popUpButtons.count >= 2, "Language and microphone pickers")
        attachScreenshot("calibration")
        done.click()
        let gone = NSPredicate(format: "exists == false")
        expectation(for: gone, evaluatedWith: done)
        waitForExpectations(timeout: 5)
    }

    func testSettingsShowsLivePreviewAndAllTabs() {
        launch()
        app.typeKey(",", modifierFlags: .command)
        let settings = app.windows.matching(NSPredicate(format: "title IN {'General', 'Prompter', 'Voice', 'Shortcuts'}")).firstMatch
        XCTAssertTrue(settings.waitForExistence(timeout: 5))
        for tab in ["General", "Prompter", "Voice", "Shortcuts"] {
            XCTAssertTrue(app.toolbars.buttons[tab].exists, "\(tab) tab")
        }
        app.toolbars.buttons["Prompter"].click()
        XCTAssertTrue(app.descendants(matching: .any)["settings.notchPreview"].waitForExistence(timeout: 5))
        attachScreenshot("settings-prompter")
        app.toolbars.buttons["Voice"].click()
        XCTAssertTrue(app.popUpButtons["settings.microphone"].waitForExistence(timeout: 5))
        attachScreenshot("settings-voice")
        app.toolbars.buttons["Shortcuts"].click()
        XCTAssertTrue(app.staticTexts["⇧→"].waitForExistence(timeout: 5))
    }
}
