import AppKit
import SwiftUI
import VaasiCore

struct SettingsView: View {
    var body: some View {
        TabView {
            Tab("General", systemImage: "gearshape") { GeneralSettings() }
            Tab("Prompter", systemImage: "text.alignleft") { PrompterSettings() }
            Tab("Voice", systemImage: "waveform") { VoiceSettings() }
            Tab("Shortcuts", systemImage: "keyboard") { ShortcutSettings() }
        }
        .frame(width: 560)
        .scenePadding()
    }
}

private struct GeneralSettings: View {
    @Environment(Preferences.self) private var preferences
    @Environment(Updater.self) private var updater

    var body: some View {
        @Bindable var preferences = preferences
        Form {
            Picker("Scrolling", selection: $preferences.scrollMode) {
                Text("Follow my voice").tag(ScrollMode.voice)
                Text("Continuous").tag(ScrollMode.continuous)
            }
            .pickerStyle(.radioGroup)
            .accessibilityIdentifier("settings.scrollMode")
            SpeedSlider(index: $preferences.speedIndex)
            Picker("Countdown", selection: $preferences.countdownSeconds) {
                Text("Off").tag(0)
                Text("3 seconds").tag(3)
                Text("5 seconds").tag(5)
                Text("10 seconds").tag(10)
            }
            Toggle("Pause while the pointer is over the prompter", isOn: $preferences.hoverToPause)
            Toggle("Hide the Vaasi window from screen sharing", isOn: $preferences.hideMainWindowFromCapture)
            Text("The prompter itself is always hidden from screen sharing and screenshots.")
                .font(.footnote)
                .foregroundStyle(.secondary)
            Section {
                Toggle("Check for updates automatically", isOn: Binding(
                    get: { updater.automaticallyChecks },
                    set: { updater.automaticallyChecks = $0 }
                ))
                Button("Check Now") { updater.checkForUpdates() }
                    .disabled(!updater.canCheckForUpdates)
            }
        }
        .formStyle(.grouped)
    }
}

struct SpeedSlider: View {
    @Binding var index: Int

    var body: some View {
        LabeledContent("Default speed") {
            HStack {
                Slider(value: Binding(get: { Double(index) }, set: { index = Int($0.rounded()) }),
                       in: 0...Double(ScrollEngine.speedSteps.count - 1), step: 1)
                Text("\(Int(ScrollEngine.speedSteps[index])) pt/s")
                    .monospacedDigit()
                    .frame(width: 64, alignment: .trailing)
            }
        }
    }
}

private struct PrompterSettings: View {
    @Environment(Preferences.self) private var preferences

    var body: some View {
        @Bindable var preferences = preferences
        Form {
            Section {
                NotchPreview()
                    .frame(height: 190)
                    .frame(maxWidth: .infinity)
                    .listRowInsets(EdgeInsets())
            }
            Picker("Show the prompter", selection: $preferences.placement) {
                ForEach(PrompterPlacement.allCases) { Text($0.title).tag($0) }
            }
            .pickerStyle(.segmented)
            Picker("Font", selection: $preferences.font) {
                ForEach(PrompterFont.allCases) { Text($0.title).tag($0) }
            }
            LabeledSlider(title: "Text size", value: $preferences.textSize, range: 12...64, unit: "pt")
            LabeledSlider(title: "Line spacing", value: $preferences.lineSpacing, range: 0...24, unit: "pt")
            ColorRow(title: "Text color", hex: $preferences.textColorHex, choices: ColorChoice.text)
            LabeledSlider(title: "Notch width", value: $preferences.notchWidth,
                          range: Double(PrompterLayout.minNotchSize.width)...Double(PrompterLayout.maxNotchSize.width), unit: "pt")
            LabeledSlider(title: "Notch height", value: $preferences.notchHeight,
                          range: Double(PrompterLayout.minNotchSize.height)...Double(PrompterLayout.maxNotchSize.height), unit: "pt")
            Text("You can also drag the prompter's edges to resize it while it's running.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .formStyle(.grouped)
    }
}

private struct VoiceSettings: View {
    @Environment(Preferences.self) private var preferences
    @Environment(AudioDevices.self) private var devices
    @State private var tester = MicTester()
    @State private var locales: [Locale] = []

    var body: some View {
        @Bindable var preferences = preferences
        Form {
            Section {
                Picker("Microphone", selection: $preferences.microphoneUID) {
                    Text("System default").tag(String?.none)
                    ForEach(devices.inputs) { Text($0.name).tag(String?.some($0.uid)) }
                }
                .accessibilityIdentifier("settings.microphone")
                LevelMeterRow(level: tester.level, isSpeaking: tester.isSpeaking, error: tester.error)
                LabeledSlider(title: "Sensitivity", value: $preferences.sensitivity, range: 0...1, unit: nil)
                Toggle("Boost quiet microphones automatically", isOn: $preferences.autoGain)
                Toggle("Reduce background noise", isOn: $preferences.noiseSuppression)
            }
            Section {
                Toggle("Follow my place in the script", isOn: $preferences.adaptiveTempo)
                Text("Recognizes your speech on this Mac so the prompter keeps pace with you, not just with your voice level.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                Picker("Language", selection: $preferences.speechLocale) {
                    if !locales.contains(where: { $0.identifier == preferences.speechLocale }) {
                        Text(Locale.current.localizedString(forIdentifier: preferences.speechLocale) ?? preferences.speechLocale)
                            .tag(preferences.speechLocale)
                    }
                    ForEach(locales, id: \.identifier) { locale in
                        Text(Locale.current.localizedString(forIdentifier: locale.identifier) ?? locale.identifier)
                            .tag(locale.identifier)
                    }
                }
            }
            Section {
                Toggle("Show voice beam", isOn: $preferences.showsVoiceBeam)
                ColorRow(title: "Beam color", hex: $preferences.beamColorHex, choices: ColorChoice.beam)
            }
        }
        .formStyle(.grouped)
        .task { locales = await SpeechSession.supportedLocales() }
        .onAppear { restartTester() }
        .onDisappear { tester.stop() }
        .onChange(of: preferences.microphoneUID) { restartTester() }
        .onChange(of: preferences.noiseSuppression) { restartTester() }
    }

    private func restartTester() {
        guard !LaunchOptions.current.isUITesting else { return }
        tester.start(device: devices.resolve(uid: preferences.microphoneUID), preferences: preferences)
    }
}

private struct ShortcutSettings: View {
    var body: some View {
        Form {
            Section {
                ForEach(PrompterCommand.allCases) { command in
                    LabeledContent(command.title) {
                        Text(command.shortcut.label)
                            .font(.system(.body, design: .monospaced))
                            .foregroundStyle(.secondary)
                    }
                }
            } footer: {
                Text("These work from any app while the prompter is running. Start the prompter with ⌘↩ in Vaasi.")
            }
        }
        .formStyle(.grouped)
    }
}

struct LevelMeterRow: View {
    let level: Double
    let isSpeaking: Bool
    let error: String?

    var body: some View {
        LabeledContent("Input level") {
            if let error {
                Text(error).foregroundStyle(.red).font(.footnote)
            } else {
                HStack(spacing: 8) {
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            Capsule().fill(.quaternary)
                            Capsule().fill(isSpeaking ? Color.green : Color.accentColor)
                                .frame(width: geo.size.width * level)
                        }
                    }
                    .frame(height: 8)
                    Text(isSpeaking ? "Speaking" : "Quiet")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .frame(width: 60, alignment: .trailing)
                }
            }
        }
    }
}

struct LabeledSlider: View {
    let title: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    let unit: String?

    var body: some View {
        LabeledContent(title) {
            HStack {
                Slider(value: $value, in: range)
                if let unit {
                    Text("\(Int(value)) \(unit)").monospacedDigit().frame(width: 64, alignment: .trailing)
                }
            }
        }
    }
}

struct ColorRow: View {
    let title: String
    @Binding var hex: String
    let choices: [ColorChoice]

    var body: some View {
        LabeledContent(title) {
            HStack(spacing: 8) {
                ForEach(choices) { choice in
                    Button { hex = choice.hex } label: {
                        Circle()
                            .fill(Color(hex: choice.hex))
                            .frame(width: 20, height: 20)
                            .overlay(Circle().strokeBorder(.primary.opacity(0.25)))
                            .overlay {
                                if hex.uppercased() == choice.hex {
                                    Circle().strokeBorder(Color.accentColor, lineWidth: 2).padding(-3)
                                }
                            }
                    }
                    .buttonStyle(.plain)
                    .help(choice.name)
                    .accessibilityLabel(choice.name)
                }
                ColorPicker("", selection: Binding(get: { Color(hex: hex) },
                                                   set: { hex = NSColor($0).hexString }),
                            supportsOpacity: false)
                    .labelsHidden()
            }
        }
    }
}

/// Scaled-down prompter showing the current look, updated as you change settings.
struct NotchPreview: View {
    @Environment(Preferences.self) private var preferences

    private let sample = "Say what you meant to say. Your words sit right under the camera, so you keep eye contact."

    var body: some View {
        GeometryReader { geo in
            let scale = min(1, (geo.size.width - 40) / max(preferences.notchWidth, 1), (geo.size.height - 30) / max(preferences.notchHeight + 32, 1))
            ZStack(alignment: .top) {
                LinearGradient(colors: [Color(white: 0.75), Color(white: 0.55)], startPoint: .top, endPoint: .bottom)
                ZStack(alignment: .top) {
                    NotchShape().fill(.black)
                    if preferences.showsVoiceBeam {
                        VoiceBeam(meter: PreviewMeter.shared, color: preferences.beamColor)
                            .clipShape(NotchShape())
                    }
                    Text(sample)
                        .font(Font(preferences.font.nsFont(size: preferences.textSize)))
                        .lineSpacing(preferences.lineSpacing)
                        .foregroundStyle(preferences.textColor)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 22)
                        .padding(.top, 32 + 8)
                    Capsule().fill(Color(white: 0.08)).frame(width: 12, height: 12).padding(.top, 10)
                }
                .frame(width: preferences.notchWidth, height: preferences.notchHeight + 32)
                .clipped()
                .scaleEffect(scale, anchor: .top)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .accessibilityIdentifier("settings.notchPreview")
    }
}

@MainActor
enum PreviewMeter {
    static let shared: VoiceMeter = {
        let meter = VoiceMeter()
        meter.level = 0.45
        return meter
    }()
}
