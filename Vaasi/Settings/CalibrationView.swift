import SwiftUI

/// First-run setup: pick a language and microphone, check the level, and tune
/// sensitivity so the prompter starts and stops with your voice.
struct CalibrationView: View {
    @Environment(Preferences.self) private var preferences
    @Environment(AudioDevices.self) private var devices
    @Environment(\.dismissWindow) private var dismissWindow
    @State private var tester = MicTester()
    @State private var locales: [Locale] = []

    var body: some View {
        @Bindable var preferences = preferences
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Set up your voice")
                    .font(.system(size: 28, weight: .regular, design: .serif))
                Text("Vaasi scrolls while you talk and waits when you stop. Say a few words to check it can hear you.")
                    .foregroundStyle(.secondary)
            }
            Form {
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
                Picker("Microphone", selection: $preferences.microphoneUID) {
                    Text("System default").tag(String?.none)
                    ForEach(devices.inputs) { Text($0.name).tag(String?.some($0.uid)) }
                }
                LevelMeterRow(level: tester.level, isSpeaking: tester.isSpeaking, error: tester.error)
                LabeledSlider(title: "Sensitivity", value: $preferences.sensitivity, range: 0...1, unit: nil)
            }
            .formStyle(.grouped)
            .scrollDisabled(true)
            HStack {
                Text("You can change these any time in Settings.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Done") {
                    preferences.hasCompletedOnboarding = true
                    dismissWindow(id: "calibration")
                }
                .keyboardShortcut(.defaultAction)
                .accessibilityIdentifier("calibration.done")
            }
        }
        .padding(24)
        .frame(width: 500)
        .task { locales = await SpeechSession.supportedLocales() }
        .onAppear { restartTester() }
        .onDisappear { tester.stop() }
        .onChange(of: preferences.microphoneUID) { restartTester() }
    }

    private func restartTester() {
        guard !LaunchOptions.current.isUITesting else { return }
        tester.start(device: devices.resolve(uid: preferences.microphoneUID), preferences: preferences)
    }
}
