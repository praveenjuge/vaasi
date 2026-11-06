import SwiftData
import SwiftUI

/// Long-lived objects shared by every window.
@MainActor
final class AppModel {
    let options = LaunchOptions.current
    let preferences: Preferences
    let devices = AudioDevices()
    let prompter: PrompterController
    let library = LibraryModel()
    let container: ModelContainer

    init() {
        let defaults: UserDefaults
        if options.isUITesting {
            let suite = "com.praveenjuge.vaasi.uitests"
            UserDefaults().removePersistentDomain(forName: suite)
            defaults = UserDefaults(suiteName: suite) ?? .standard
        } else {
            defaults = .standard
        }
        preferences = Preferences(defaults: defaults)
        if options.isUITesting {
            preferences.hasCompletedOnboarding = !options.showsOnboarding
        }
        prompter = PrompterController(preferences: preferences, devices: devices, options: options)

        let configuration = ModelConfiguration(isStoredInMemoryOnly: options.isUITesting)
        do {
            container = try ModelContainer(for: Note.self, configurations: configuration)
        } catch {
            fatalError("Couldn't open the notes store: \(error)")
        }
        if !preferences.hasSeededNotes {
            StarterNotes.seed(into: container.mainContext)
            preferences.hasSeededNotes = true
        }
    }
}

@main
struct VaasiApp: App {
    @State private var app = AppModel()

    var body: some Scene {
        Window("Vaasi", id: "main") {
            LibraryView()
                .environment(app.library)
                .environment(app.prompter)
                .environment(app.preferences)
                .environment(app.devices)
                .modelContainer(app.container)
                .modifier(SettingsOpener(prompter: app.prompter))
        }
        .defaultLaunchBehavior(.presented)
        .commands { VaasiCommands(app: app) }

        Window("Set Up Vaasi", id: "calibration") {
            CalibrationView()
                .environment(app.preferences)
                .environment(app.devices)
        }
        .windowResizability(.contentSize)
        .windowStyle(.hiddenTitleBar)
        .defaultLaunchBehavior(.suppressed)
        .restorationBehavior(.disabled)

        Settings {
            SettingsView()
                .environment(app.preferences)
                .environment(app.devices)
        }
    }
}

/// Lets the prompter's silence hint open Settings.
private struct SettingsOpener: ViewModifier {
    let prompter: PrompterController
    @Environment(\.openSettings) private var openSettings

    func body(content: Content) -> some View {
        content.onAppear {
            prompter.openSettings = {
                NSApp.activate()
                openSettings()
            }
        }
    }
}

struct VaasiCommands: Commands {
    let app: AppModel
    @Environment(\.openWindow) private var openWindow

    private var context: ModelContext { app.container.mainContext }

    var body: some Commands {
        CommandGroup(replacing: .newItem) {
            Button("New Note") { app.library.createNote(in: context) }
                .keyboardShortcut("n")
            Button("Import…") { app.library.runImportPanel(into: context) }
                .keyboardShortcut("o", modifiers: [.command, .shift])
            Button("Export…") {
                if let note = app.library.selection { app.library.runExportPanel(for: note) }
            }
            .keyboardShortcut("e", modifiers: [.command, .shift])
        }
        CommandGroup(replacing: .textEditing) {
            Button("Search Notes") { app.library.searchFocusRequest += 1 }
                .keyboardShortcut("f")
        }
        CommandMenu("Prompter") {
            Button("Start") {
                if let note = app.library.selection { app.prompter.start(title: note.displayTitle, body: note.body) }
            }
            .keyboardShortcut(.return)
            Divider()
            ForEach(PrompterCommand.allCases) { command in
                Button("\(command.title)  (\(command.shortcut.label))") { app.prompter.perform(command) }
            }
            Divider()
            Button("Set Up Microphone…") { openWindow(id: "calibration") }
        }
        CommandGroup(replacing: .systemServices) {}
    }
}
