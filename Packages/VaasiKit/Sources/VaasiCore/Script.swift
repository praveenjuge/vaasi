import Foundation

/// A note's text split into cues (sections) and prepared for the prompter.
///
/// Dividers are lines made of three or more dashes. Text after the dashes names
/// the section that follows (`--- The opening`). Divider lines never appear in
/// the prompter. All ranges are UTF-16 offsets so they map directly onto
/// `NSString` / `NSTextView` layout.
public struct Script: Equatable, Sendable {
    public struct Section: Equatable, Sendable, Identifiable {
        public let id: Int
        public let name: String
        /// Range of this section's text inside `promptText`.
        public let range: NSRange
    }

    /// The text shown in the prompter: sections joined by a blank line.
    public let promptText: String
    public let sections: [Section]

    public init(body: String) {
        var sectionTexts: [(name: String?, text: String)] = []
        var currentName: String?
        var currentLines: [Substring] = []

        func flush() {
            let text = currentLines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
            if !text.isEmpty || currentName != nil {
                sectionTexts.append((currentName, text))
            }
            currentLines.removeAll()
        }

        for line in body.split(separator: "\n", omittingEmptySubsequences: false) {
            if let name = Script.dividerName(in: line) {
                flush()
                currentName = name.isEmpty ? nil : name
            } else {
                currentLines.append(line)
            }
        }
        flush()

        var prompt = ""
        var sections: [Section] = []
        for (name, text) in sectionTexts where !text.isEmpty {
            if !prompt.isEmpty { prompt += "\n\n" }
            let start = (prompt as NSString).length
            prompt += text
            let length = (text as NSString).length
            sections.append(Section(
                id: sections.count,
                name: name ?? Script.fallbackName(for: text),
                range: NSRange(location: start, length: length)
            ))
        }
        self.promptText = prompt
        self.sections = sections
    }

    /// Returns the divider's name (possibly empty) when `line` is a divider, otherwise nil.
    public static func dividerName(in line: some StringProtocol) -> String? {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard trimmed.hasPrefix("---") else { return nil }
        let rest = trimmed.drop(while: { $0 == "-" })
        // Only whitespace may separate the dashes from the name.
        if let first = rest.first, !first.isWhitespace { return nil }
        return rest.trimmingCharacters(in: .whitespaces)
    }

    /// The divider line the editor inserts.
    public static let dividerLine = "---"

    static func fallbackName(for text: String) -> String {
        let firstLine = text.split(separator: "\n", maxSplits: 1).first.map(String.init) ?? text
        let words = firstLine.split(whereSeparator: \.isWhitespace).prefix(6).joined(separator: " ")
        return words.count > 40 ? String(words.prefix(39)) + "…" : words
    }

    /// Index of the section containing the UTF-16 `offset` in `promptText`.
    public func sectionIndex(containing offset: Int) -> Int {
        guard !sections.isEmpty else { return 0 }
        var index = 0
        for section in sections where section.range.location <= offset {
            index = section.id
        }
        return index
    }
}
