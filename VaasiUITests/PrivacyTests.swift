import CoreGraphics
import XCTest

/// Checks with the window server itself that Vaasi's windows are excluded from
/// screen capture and sharing.
final class PrivacyTests: VaasiUITestCase {
    private struct WindowInfo {
        let sharingState: Int
        let layer: Int
        let bounds: CGRect
    }

    private func vaasiWindows() -> [WindowInfo] {
        let info = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]] ?? []
        return info.compactMap { window in
            guard (window[kCGWindowOwnerName as String] as? String) == "Vaasi" else { return nil }
            let bounds = window[kCGWindowBounds as String] as? [String: Double] ?? [:]
            return WindowInfo(sharingState: window[kCGWindowSharingState as String] as? Int ?? -1,
                              layer: window[kCGWindowLayer as String] as? Int ?? 0,
                              bounds: CGRect(x: bounds["X"] ?? 0, y: bounds["Y"] ?? 0,
                                             width: bounds["Width"] ?? 0, height: bounds["Height"] ?? 0))
        }
    }

    func testPrompterAndLibraryAreHiddenFromScreenCapture() {
        launch(allowCapture: false)
        // Library window: hidden by default setting.
        let library = vaasiWindows().filter { $0.layer == 0 && $0.bounds.width > 400 }
        XCTAssertFalse(library.isEmpty, "Library window is on screen")
        XCTAssertTrue(library.allSatisfy { $0.sharingState == Int(CGWindowSharingType.none.rawValue) },
                      "Library window is excluded from capture")

        select(note: "Welcome")
        startPrompter()
        let running = waitForState("running") { $0["phase"] == "running" }
        XCTAssertEqual(running["captureHidden"], "1")

        let prompter = vaasiWindows().filter { $0.layer > 0 }
        XCTAssertFalse(prompter.isEmpty, "Prompter panel is on screen above normal windows")
        XCTAssertTrue(prompter.allSatisfy { $0.sharingState == Int(CGWindowSharingType.none.rawValue) },
                      "Prompter is excluded from screen capture and sharing")
    }
}
