import Foundation
import Testing
@testable import Vaasi

@Suite("Import and export")
@MainActor
struct NoteTransferTests {
    let title = "Launch talk"
    let body = "Opening line for the talk.\n---\nSecond section with details."

    private func roundTrip(_ format: NoteTransfer.ExportFormat) throws -> NoteTransfer.ImportedNote {
        let data = try NoteTransfer.exportData(title: title, body: body, format: format)
        #expect(!data.isEmpty)
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension(format.fileExtension)
        try data.write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }
        return try NoteTransfer.importNote(from: url)
    }

    @Test func markdownKeepsTitleAndDividers() throws {
        let note = try roundTrip(.markdown)
        #expect(note.title == title)
        #expect(note.body == body)
    }

    @Test(arguments: [NoteTransfer.ExportFormat.plainText, .rtf, .docx, .html, .pdf])
    func formatsRoundTripTheText(_ format: NoteTransfer.ExportFormat) throws {
        let note = try roundTrip(format)
        #expect(note.body.contains("Opening line for the talk."))
        #expect(note.body.contains("Second section with details."))
    }

    @Test func dividersSurviveRichFormats() throws {
        for format in [NoteTransfer.ExportFormat.rtf, .docx, .html] {
            let note = try roundTrip(format)
            #expect(note.body.contains("---"), "\(format.title) keeps the cue divider")
        }
    }

    @Test func unsupportedFilesAreRejected() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("image.png")
        try Data([0x89, 0x50]).write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }
        #expect(throws: NoteTransfer.TransferError.self) { try NoteTransfer.importNote(from: url) }
    }

    @Test func importDropsIntoTheLibrary() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("Dropped script.txt")
        try "Hello from a file".write(to: url, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: url) }
        let note = try NoteTransfer.importNote(from: url)
        #expect(note.title == "Dropped script")
        #expect(note.body == "Hello from a file")
    }
}
