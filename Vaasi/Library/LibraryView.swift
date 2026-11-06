import AppKit
import SwiftData
import SwiftUI
import UniformTypeIdentifiers

/// Selection and search for the library window, shared with menu commands.
@MainActor @Observable
final class LibraryModel {
    var selection: Note?
    var searchText = ""
    var searchFocusRequest = 0
    var importError: String?

    func matches(_ note: Note) -> Bool {
        let query = searchText.trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty else { return true }
        return note.title.localizedStandardContains(query) || note.body.localizedStandardContains(query)
    }

    /// Text around the first match, for search results.
    func snippet(for note: Note) -> String? {
        let query = searchText.trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty, let range = note.body.range(of: query, options: [.caseInsensitive, .diacriticInsensitive]) else { return nil }
        let start = note.body.index(range.lowerBound, offsetBy: -30, limitedBy: note.body.startIndex) ?? note.body.startIndex
        let end = note.body.index(range.upperBound, offsetBy: 60, limitedBy: note.body.endIndex) ?? note.body.endIndex
        let text = note.body[start..<end].replacingOccurrences(of: "\n", with: " ")
        return (start > note.body.startIndex ? "…" : "") + text + (end < note.body.endIndex ? "…" : "")
    }

    @discardableResult
    func createNote(in context: ModelContext, title: String = "", body: String = "") -> Note {
        let note = Note(title: title, body: body)
        context.insert(note)
        searchText = ""
        selection = note
        return note
    }

    func importFiles(_ urls: [URL], into context: ModelContext) {
        var last: Note?
        for url in urls {
            let scoped = url.startAccessingSecurityScopedResource()
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }
            do {
                let imported = try NoteTransfer.importNote(from: url)
                let note = Note(title: imported.title, body: imported.body)
                context.insert(note)
                last = note
            } catch {
                importError = error.localizedDescription
            }
        }
        if let last {
            searchText = ""
            selection = last
        }
    }

    func runImportPanel(into context: ModelContext) {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = NoteTransfer.importableTypes
        panel.allowsMultipleSelection = true
        panel.prompt = "Import"
        if panel.runModal() == .OK { importFiles(panel.urls, into: context) }
    }

    func runExportPanel(for note: Note) {
        let panel = NSSavePanel()
        let picker = NSPopUpButton()
        NoteTransfer.ExportFormat.allCases.forEach { picker.addItem(withTitle: $0.title) }
        let accessory = NSStackView(views: [NSTextField(labelWithString: "Format:"), picker])
        accessory.edgeInsets = NSEdgeInsets(top: 8, left: 8, bottom: 8, right: 8)
        panel.accessoryView = accessory
        panel.nameFieldStringValue = note.displayTitle
        panel.allowedContentTypes = [NoteTransfer.ExportFormat.markdown.contentType]
        let handler = PickerTarget { index in
            panel.allowedContentTypes = [NoteTransfer.ExportFormat.allCases[index].contentType]
        }
        picker.target = handler
        picker.action = #selector(PickerTarget.changed(_:))
        guard panel.runModal() == .OK, let url = panel.url else { return }
        let format = NoteTransfer.ExportFormat.allCases[picker.indexOfSelectedItem]
        do {
            try NoteTransfer.exportData(title: note.displayTitle, body: note.body, format: format).write(to: url)
        } catch {
            importError = error.localizedDescription
        }
        _ = handler
    }
}

@MainActor
private final class PickerTarget: NSObject {
    let onChange: (Int) -> Void
    init(onChange: @escaping (Int) -> Void) { self.onChange = onChange }
    @objc func changed(_ sender: NSPopUpButton) { onChange(sender.indexOfSelectedItem) }
}

struct LibraryView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.openWindow) private var openWindow
    @Environment(LibraryModel.self) private var library
    @Environment(PrompterController.self) private var prompter
    @Environment(Preferences.self) private var preferences
    @Query(sort: \Note.updatedAt, order: .reverse) private var notes: [Note]
    @FocusState private var searchFocused: Bool
    @State private var pendingDelete: Note?
    @State private var isDropTargeted = false

    var body: some View {
        @Bindable var library = library
        NavigationSplitView {
            List(selection: $library.selection) {
                ForEach(notes.filter(library.matches)) { note in
                    NoteRow(note: note, snippet: library.snippet(for: note))
                        .tag(note)
                        .contextMenu {
                            Button("Start Prompter") { start(note) }
                            Button("Export…") { library.runExportPanel(for: note) }
                            Divider()
                            Button("Delete…", role: .destructive) { pendingDelete = note }
                        }
                }
            }
            .accessibilityIdentifier("library.list")
            .searchable(text: $library.searchText, placement: .sidebar, prompt: "Search notes")
            .searchFocused($searchFocused)
            .onDeleteCommand { pendingDelete = library.selection }
            .navigationSplitViewColumnWidth(min: 200, ideal: 240, max: 360)
            .toolbar {
                ToolbarItem {
                    Button { library.createNote(in: context) } label: { Label("New Note", systemImage: "square.and.pencil") }
                        .accessibilityIdentifier("library.newNote")
                }
            }
        } detail: {
            if let note = library.selection {
                NoteDetail(note: note, onStart: { start(note) })
                    .id(note.id)
            } else {
                ContentUnavailableView("No Note Selected", systemImage: "text.alignleft",
                                       description: Text("Pick a note or create a new one."))
            }
        }
        .frame(minWidth: 720, minHeight: 460)
        .background(WindowAccessor { window in
            prompter.mainWindow = window
            window.sharingType = preferences.hideMainWindowFromCapture ? LaunchOptions.current.hiddenSharingType : .readOnly
        })
        .onChange(of: preferences.hideMainWindowFromCapture) { _, hidden in
            prompter.mainWindow?.sharingType = hidden ? LaunchOptions.current.hiddenSharingType : .readOnly
        }
        .onChange(of: library.searchFocusRequest) { searchFocused = true }
        .onAppear {
            if library.selection == nil { library.selection = notes.first }
            if !preferences.hasCompletedOnboarding { openWindow(id: "calibration") }
        }
        .onDrop(of: [.fileURL], isTargeted: $isDropTargeted) { providers in
            loadDroppedFiles(providers)
            return true
        }
        .overlay {
            if isDropTargeted {
                RoundedRectangle(cornerRadius: 12).strokeBorder(Color.accentColor, lineWidth: 3).padding(6)
                    .allowsHitTesting(false)
            }
        }
        .confirmationDialog("Delete “\(pendingDelete?.displayTitle ?? "")”?",
                            isPresented: Binding(get: { pendingDelete != nil }, set: { if !$0 { pendingDelete = nil } })) {
            Button("Delete", role: .destructive) { deletePending() }
            Button("Cancel", role: .cancel) { pendingDelete = nil }
        } message: {
            Text("This can't be undone.")
        }
        .alert("Couldn't complete that", isPresented: Binding(get: { library.importError != nil }, set: { if !$0 { library.importError = nil } })) {
            Button("OK") { library.importError = nil }
        } message: {
            Text(library.importError ?? "")
        }
    }

    private func start(_ note: Note) {
        prompter.start(title: note.displayTitle, body: note.body)
    }

    private func deletePending() {
        guard let note = pendingDelete else { return }
        let remaining = notes.filter { $0 != note }
        if library.selection == note { library.selection = remaining.first }
        context.delete(note)
        pendingDelete = nil
    }

    private func loadDroppedFiles(_ providers: [NSItemProvider]) {
        for provider in providers {
            _ = provider.loadObject(ofClass: URL.self) { @Sendable url, _ in
                guard let url else { return }
                Task { @MainActor in library.importFiles([url], into: context) }
            }
        }
    }
}

struct NoteRow: View {
    let note: Note
    let snippet: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(note.displayTitle)
                .font(.headline)
                .lineLimit(1)
            Text(snippet ?? note.preview)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .lineLimit(2)
        }
        .padding(.vertical, 3)
    }
}

struct NoteDetail: View {
    @Bindable var note: Note
    let onStart: () -> Void
    @Environment(LibraryModel.self) private var library
    @Environment(Preferences.self) private var preferences

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            TextField("Title", text: $note.title, axis: .vertical)
                .font(.system(size: 34, weight: .regular, design: .serif))
                .textFieldStyle(.plain)
                .accessibilityIdentifier("editor.title")
            ScriptEditor(text: $note.body)
        }
        .padding(.horizontal, 48)
        .padding(.top, 28)
        .frame(maxWidth: 820)
        .frame(maxWidth: .infinity)
        .onChange(of: note.title) { note.touch() }
        .onChange(of: note.body) { note.touch() }
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Picker("Placement", selection: Bindable(preferences).placement) {
                    Label("Notch", systemImage: "rectangle.topthird.inset.filled").tag(PrompterPlacement.notch)
                    Label("Floating", systemImage: "macwindow").tag(PrompterPlacement.floating)
                }
                .pickerStyle(.segmented)
                .help("Where the prompter appears")
                Button { library.runExportPanel(for: note) } label: { Label("Export", systemImage: "square.and.arrow.up") }
                Button(action: onStart) { Label("Start", systemImage: "play.fill") }
                    .help("Start the prompter (⌘↩)")
                    .accessibilityIdentifier("library.start")
            }
        }
    }
}

/// Hands the hosting NSWindow to a callback once the view is in a window.
struct WindowAccessor: NSViewRepresentable {
    let onWindow: (NSWindow) -> Void

    func makeNSView(context: Context) -> NSView {
        let view = WindowObservingView()
        view.onWindow = onWindow
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {}

    final class WindowObservingView: NSView {
        var onWindow: ((NSWindow) -> Void)?
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            if let window { onWindow?(window) }
        }
    }
}
