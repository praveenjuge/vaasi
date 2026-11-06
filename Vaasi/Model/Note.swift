import Foundation
import SwiftData
import VaasiCore

@Model
final class Note {
    var id: UUID = UUID()
    var title: String = ""
    var body: String = ""
    var createdAt: Date = Date.now
    var updatedAt: Date = Date.now

    init(title: String = "", body: String = "") {
        self.title = title
        self.body = body
    }

    var displayTitle: String {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty { return trimmed }
        let firstLine = body.split(separator: "\n").first.map(String.init) ?? ""
        return firstLine.isEmpty ? "Untitled" : String(firstLine.prefix(60))
    }

    var preview: String {
        body.split(whereSeparator: \.isNewline)
            .first { Script.dividerName(in: $0) == nil && !$0.trimmingCharacters(in: .whitespaces).isEmpty }
            .map { String($0.prefix(120)) } ?? ""
    }

    func touch() { updatedAt = .now }
}

enum StarterNotes {
    static func welcome() -> Note { Note(
        title: "Welcome",
        body: """
        This is Vaasi, a teleprompter that sits right under your camera.

        Write what you want to say here. When you press Start, the text appears in the notch at the top of your screen, so you can read it and still look at the person you're talking to.

        Vaasi listens while you talk. It scrolls when you speak and waits when you stop. Hover over the prompter to pause it.

        Only you can see it. The prompter stays out of screen sharing and screenshots.

        Everything you write stays on this Mac.
        """
    ) }

    static func cues() -> Note { Note(
        title: "Using cues",
        body: """
        Cues split a script into sections you can jump between while you present.
        --- Adding a divider
        Type three dashes on their own line to start a new section. You can also right-click in the editor and choose Insert Divider.
        --- Naming a section
        Write a name after the dashes, like this section's divider. Unnamed sections use their first few words.
        --- Moving between sections
        While the prompter runs, use the arrows under it or the numbered list to jump to any section, then carry on from there.
        """
    ) }

    @MainActor
    static func seed(into context: ModelContext) {
        let welcome = welcome()
        let cues = cues()
        // Welcome should be the newest so it opens first.
        cues.updatedAt = .now.addingTimeInterval(-1)
        context.insert(cues)
        context.insert(welcome)
    }
}
