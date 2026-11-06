import AppKit
import SwiftUI

/// Where the camera notch is on a screen. Screens without a notch get a
/// menu-bar-height strip so the prompter still hugs the top edge.
struct NotchMetrics: Equatable {
    let hasNotch: Bool
    let width: CGFloat
    let height: CGFloat

    @MainActor
    static func of(_ screen: NSScreen) -> NotchMetrics {
        let top = screen.safeAreaInsets.top
        if top > 0, let left = screen.auxiliaryTopLeftArea, let right = screen.auxiliaryTopRightArea {
            return NotchMetrics(hasNotch: true, width: screen.frame.width - left.width - right.width, height: top)
        }
        let menuBar = screen.frame.maxY - screen.visibleFrame.maxY
        return NotchMetrics(hasNotch: false, width: 0, height: menuBar > 0 ? menuBar : 24)
    }
}

/// Size of the band under the prompter that holds the cue bar and hints.
enum PrompterLayout {
    static let accessoryHeight: CGFloat = 52
    static let notchSideInset: CGFloat = 10
    static let minNotchSize = CGSize(width: 260, height: 70)
    static let maxNotchSize = CGSize(width: 1100, height: 600)
    static let minFloatingSize = CGSize(width: 260, height: 140)
}

/// The prompter window: never takes focus, floats over everything including
/// full-screen apps, shows on every Space, and is excluded from screen capture.
final class PrompterPanel: NSPanel {
    init(placement: PrompterPlacement) {
        var style: NSWindow.StyleMask = [.borderless, .nonactivatingPanel, .fullSizeContentView]
        if placement == .floating { style.insert(.resizable) }
        super.init(contentRect: .zero, styleMask: style, backing: .buffered, defer: false)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = placement == .floating
        level = .statusBar
        isFloatingPanel = true
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        isMovableByWindowBackground = placement == .floating
        sharingType = LaunchOptions.current.hiddenSharingType
        animationBehavior = .none
        var behavior: NSWindow.CollectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        if placement == .notch { behavior.insert(.stationary) }
        collectionBehavior = behavior
        minSize = PrompterLayout.minFloatingSize
        setAccessibilityIdentifier("prompter.window")
    }

    /// The notch prompter covers the menu bar strip on purpose; don't let AppKit
    /// push it down below the menu bar.
    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect {
        frameRect
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    /// Frame for the notch prompter: centered on the notch, flush with the top
    /// of the screen, covering the notch and extending below it.
    @MainActor
    static func notchFrame(on screen: NSScreen, size: CGSize) -> NSRect {
        let notch = NotchMetrics.of(screen)
        let width = max(size.width, notch.width + PrompterLayout.notchSideInset * 2 + 80)
        let height = notch.height + size.height + PrompterLayout.accessoryHeight
        return NSRect(x: screen.frame.midX - width / 2, y: screen.frame.maxY - height, width: width, height: height)
    }

    @MainActor
    static func defaultFloatingFrame(on screen: NSScreen) -> NSRect {
        let size = CGSize(width: 520, height: 300)
        let visible = screen.visibleFrame
        return NSRect(x: visible.midX - size.width / 2, y: visible.maxY - size.height - 40,
                      width: size.width, height: size.height)
    }
}

/// Hosting view that lets the first click on a button act, even though the
/// prompter never becomes key.
final class FirstMouseHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}
