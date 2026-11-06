import AppKit

/// Switches the verification loop uses to drive the real app deterministically.
/// None of these are set in normal use.
struct LaunchOptions: Sendable {
    /// Sharing type for windows that should stay out of screen capture.
    var hiddenSharingType: NSWindow.SharingType { allowsCapture ? .readOnly : .none }

    /// In-memory notes, fresh preferences, onboarding skipped. Also on when the
    /// app hosts unit tests, so tests never touch real notes or settings.
    let isUITesting: Bool
    /// Show first-run calibration even in UI-test mode.
    let showsOnboarding: Bool
    /// Let screenshots see Vaasi's windows, for visual verification only. The
    /// capture-hiding check runs without it.
    let allowsCapture: Bool
    /// Replace the microphone with synthesized speech, e.g.
    /// `speak:Hello there|silence:3|speak:More words`. The audio runs through
    /// the real level meter, voice detector and speech recognizer.
    let synthesizedAudio: String?

    static let current = LaunchOptions(arguments: ProcessInfo.processInfo.arguments,
                                       environment: ProcessInfo.processInfo.environment)

    init(arguments: [String], environment: [String: String]) {
        isUITesting = arguments.contains("-UITesting") || environment["XCTestConfigurationFilePath"] != nil
        showsOnboarding = arguments.contains("-ShowOnboarding")
        allowsCapture = arguments.contains("-AllowCapture")
        synthesizedAudio = environment["VAASI_SYNTH_AUDIO"]
    }
}
