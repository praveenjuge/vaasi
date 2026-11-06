import Foundation
import Testing
@testable import VaasiCore

@Suite("Script cues")
struct ScriptTests {
    @Test func plainTextIsOneSection() {
        let script = Script(body: "Hello there.\nSecond line.")
        #expect(script.sections.count == 1)
        #expect(script.promptText == "Hello there.\nSecond line.")
        #expect(script.sections[0].name == "Hello there.")
    }

    @Test func dividersSplitAndNameSections() {
        let body = """
        Opening words here.
        --- Main point
        The middle part.
        ---
        Closing thoughts now.
        """
        let script = Script(body: body)
        #expect(script.sections.map(\.name) == ["Opening words here.", "Main point", "Closing thoughts now."])
        #expect(!script.promptText.contains("---"))
        let ns = script.promptText as NSString
        #expect(ns.substring(with: script.sections[1].range) == "The middle part.")
        #expect(ns.substring(with: script.sections[2].range) == "Closing thoughts now.")
    }

    @Test func emptySectionsAreDropped() {
        let script = Script(body: "---\n---\nOnly text\n---\n")
        #expect(script.sections.count == 1)
        #expect(script.promptText == "Only text")
    }

    @Test func dividerDetection() {
        #expect(Script.dividerName(in: "---") == "")
        #expect(Script.dividerName(in: "  ----- Intro ") == "Intro")
        #expect(Script.dividerName(in: "--") == nil)
        #expect(Script.dividerName(in: "---x") == nil)
        #expect(Script.dividerName(in: "text ---") == nil)
    }

    @Test func sectionLookupByOffset() {
        let script = Script(body: "One\n---\nTwo\n---\nThree")
        #expect(script.sectionIndex(containing: 0) == 0)
        #expect(script.sectionIndex(containing: script.sections[1].range.location) == 1)
        #expect(script.sectionIndex(containing: (script.promptText as NSString).length) == 2)
    }

    @Test func unicodeRangesAreUTF16() {
        let script = Script(body: "Emoji 👋 first\n--- Two\nZażółć gęślą")
        let ns = script.promptText as NSString
        #expect(ns.substring(with: script.sections[1].range) == "Zażółć gęślą")
    }
}
