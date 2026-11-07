import AppKit
import Observation
import SwiftUI
import VaasiCore

enum PrompterPlacement: String, CaseIterable, Identifiable {
    case notch
    case floating

    var id: String { rawValue }
    var title: String { self == .notch ? "Notch" : "Floating window" }
}

enum PrompterFont: String, CaseIterable, Identifiable {
    case mono, sans, serif

    var id: String { rawValue }
    var title: String {
        switch self {
        case .mono: "Monospaced"
        case .sans: "Sans serif"
        case .serif: "Serif"
        }
    }

    func nsFont(size: CGFloat) -> NSFont {
        switch self {
        case .mono: return .monospacedSystemFont(ofSize: size, weight: .medium)
        case .sans: return .systemFont(ofSize: size, weight: .medium)
        case .serif:
            let base = NSFont.systemFont(ofSize: size, weight: .medium)
            let descriptor = base.fontDescriptor.withDesign(.serif) ?? base.fontDescriptor
            return NSFont(descriptor: descriptor, size: size) ?? base
        }
    }
}

/// Named color choices offered in Settings. Custom colors are stored as hex too.
struct ColorChoice: Identifiable, Hashable {
    let name: String
    let hex: String
    var id: String { hex }

    static let text: [ColorChoice] = [
        ColorChoice(name: "White", hex: "#FFFFFF"),
        ColorChoice(name: "Cream", hex: "#F3E9D2"),
        ColorChoice(name: "Yellow", hex: "#FFE066"),
        ColorChoice(name: "Green", hex: "#7CF29A"),
        ColorChoice(name: "Cyan", hex: "#7FDBFF"),
        ColorChoice(name: "Pink", hex: "#FF9ECF"),
    ]

    static let beam: [ColorChoice] = [
        ColorChoice(name: "Orange", hex: "#FF6B12"),
        ColorChoice(name: "Blue", hex: "#4F5BFF"),
        ColorChoice(name: "Violet", hex: "#9B5CFF"),
        ColorChoice(name: "Teal", hex: "#22C7B8"),
        ColorChoice(name: "White", hex: "#FFFFFF"),
    ]
}

/// All user settings, persisted in UserDefaults. UI tests get a throwaway suite.
@MainActor @Observable
final class Preferences {
    @ObservationIgnored private let defaults: UserDefaults

    // Prompter
    var placement: PrompterPlacement { didSet { save(placement.rawValue, "placement") } }
    var textSize: Double { didSet { save(textSize, "textSize") } }
    var lineSpacing: Double { didSet { save(lineSpacing, "lineSpacing") } }
    var font: PrompterFont { didSet { save(font.rawValue, "font") } }
    var textColorHex: String { didSet { save(textColorHex, "textColor") } }
    /// Notch prompter size (points, below the notch).
    var notchWidth: Double { didSet { save(notchWidth, "notchWidth") } }
    var notchHeight: Double { didSet { save(notchHeight, "notchHeight") } }
    var floatingFrame: String { didSet { save(floatingFrame, "floatingFrame") } }

    // Playback
    var scrollMode: ScrollMode { didSet { save(scrollMode.rawValue, "scrollMode") } }
    var speedIndex: Int { didSet { save(speedIndex, "speedIndex") } }
    var adaptiveTempo: Bool { didSet { save(adaptiveTempo, "adaptiveTempo") } }
    var countdownSeconds: Int { didSet { save(countdownSeconds, "countdownSeconds") } }
    var hoverToPause: Bool { didSet { save(hoverToPause, "hoverToPause") } }
    var hideMainWindowFromCapture: Bool { didSet { save(hideMainWindowFromCapture, "hideMainWindowFromCapture") } }

    // Voice
    var microphoneUID: String? { didSet { save(microphoneUID, "microphoneUID") } }
    var sensitivity: Double { didSet { save(sensitivity, "sensitivity") } }
    var autoGain: Bool { didSet { save(autoGain, "autoGain") } }
    var noiseSuppression: Bool { didSet { save(noiseSuppression, "noiseSuppression") } }
    var showsVoiceBeam: Bool { didSet { save(showsVoiceBeam, "showsVoiceBeam") } }
    var beamColorHex: String { didSet { save(beamColorHex, "beamColor") } }
    var speechLocale: String { didSet { save(speechLocale, "speechLocale") } }

    var hasCompletedOnboarding: Bool { didSet { save(hasCompletedOnboarding, "hasCompletedOnboarding") } }
    var hasSeededNotes: Bool { didSet { save(hasSeededNotes, "hasSeededNotes") } }

    init(defaults: UserDefaults) {
        self.defaults = defaults
        placement = PrompterPlacement(rawValue: defaults.string(forKey: "placement") ?? "") ?? .notch
        textSize = Preferences.double(defaults, "textSize", 22)
        lineSpacing = Preferences.double(defaults, "lineSpacing", 6)
        font = PrompterFont(rawValue: defaults.string(forKey: "font") ?? "") ?? .mono
        textColorHex = defaults.string(forKey: "textColor") ?? "#FFFFFF"
        notchWidth = Preferences.double(defaults, "notchWidth", 440)
        notchHeight = Preferences.double(defaults, "notchHeight", 150)
        floatingFrame = defaults.string(forKey: "floatingFrame") ?? ""
        scrollMode = ScrollMode(rawValue: defaults.string(forKey: "scrollMode") ?? "") ?? .voice
        speedIndex = Preferences.int(defaults, "speedIndex", ScrollEngine.defaultSpeedIndex)
        adaptiveTempo = Preferences.bool(defaults, "adaptiveTempo", true)
        countdownSeconds = Preferences.int(defaults, "countdownSeconds", 3)
        hoverToPause = Preferences.bool(defaults, "hoverToPause", true)
        hideMainWindowFromCapture = Preferences.bool(defaults, "hideMainWindowFromCapture", true)
        microphoneUID = defaults.string(forKey: "microphoneUID")
        sensitivity = Preferences.double(defaults, "sensitivity", 0.6)
        autoGain = Preferences.bool(defaults, "autoGain", true)
        noiseSuppression = defaults.bool(forKey: "noiseSuppression")
        showsVoiceBeam = Preferences.bool(defaults, "showsVoiceBeam", true)
        beamColorHex = defaults.string(forKey: "beamColor") ?? "#FF6B12"
        speechLocale = defaults.string(forKey: "speechLocale") ?? Locale.current.identifier
        hasCompletedOnboarding = defaults.bool(forKey: "hasCompletedOnboarding")
        hasSeededNotes = defaults.bool(forKey: "hasSeededNotes")
    }

    // Converting getters: values passed on the command line arrive as strings.
    private static func double(_ defaults: UserDefaults, _ key: String, _ fallback: Double) -> Double {
        defaults.object(forKey: key) == nil ? fallback : defaults.double(forKey: key)
    }

    private static func int(_ defaults: UserDefaults, _ key: String, _ fallback: Int) -> Int {
        defaults.object(forKey: key) == nil ? fallback : defaults.integer(forKey: key)
    }

    private static func bool(_ defaults: UserDefaults, _ key: String, _ fallback: Bool) -> Bool {
        defaults.object(forKey: key) == nil ? fallback : defaults.bool(forKey: key)
    }

    var textColor: Color { Color(hex: textColorHex) }
    var beamColor: Color { Color(hex: beamColorHex) }

    private func save(_ value: Any?, _ key: String) {
        defaults.set(value, forKey: key)
    }
}

extension Color {
    init(hex: String) {
        self.init(nsColor: NSColor(hex: hex) ?? .white)
    }
}

extension NSColor {
    convenience init?(hex: String) {
        let digits = hex.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        guard digits.count == 6, let value = UInt32(digits, radix: 16) else { return nil }
        self.init(srgbRed: CGFloat((value >> 16) & 0xFF) / 255,
                  green: CGFloat((value >> 8) & 0xFF) / 255,
                  blue: CGFloat(value & 0xFF) / 255,
                  alpha: 1)
    }

    var hexString: String {
        let c = usingColorSpace(.sRGB) ?? self
        return String(format: "#%02X%02X%02X",
                      Int((c.redComponent * 255).rounded()),
                      Int((c.greenComponent * 255).rounded()),
                      Int((c.blueComponent * 255).rounded()))
    }
}
