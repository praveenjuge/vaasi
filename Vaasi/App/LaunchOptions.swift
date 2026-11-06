import Foundation

/// Switches the verification loop uses to drive the real app deterministically.
/// None of these are set in normal use.
struct LaunchOptions: Sendable {
    /// In-memory notes, fresh preferences, onboarding skipped.
    let isUITesting: Bool
    /// Show first-run calibration even in UI-test mode.
    let showsOnboarding: Bool
    /// Replace the microphone with synthesized speech, e.g.
    /// `speak:Hello there|silence:3|speak:More words`. The audio runs through
    /// the real level meter, voice detector and speech recognizer.
    let synthesizedAudio: String?

    static let current = LaunchOptions(arguments: ProcessInfo.processInfo.arguments,
                                       environment: ProcessInfo.processInfo.environment)

    init(arguments: [String], environment: [String: String]) {
        isUITesting = arguments.contains("-UITesting")
        showsOnboarding = arguments.contains("-ShowOnboarding")
        synthesizedAudio = environment["VAASI_SYNTH_AUDIO"]
    }
}
