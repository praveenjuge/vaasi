import AppKit
import SwiftUI
import VaasiCore

/// Text view for scripts: monospaced, dims divider lines, and offers
/// "Insert Divider" in its right-click menu.
final class ScriptTextView: NSTextView {
    static let insertDividerTitle = "Insert Divider"

    override func menu(for event: NSEvent) -> NSMenu? {
        let menu = super.menu(for: event) ?? NSMenu()
        let item = NSMenuItem(title: Self.insertDividerTitle, action: #selector(insertDivider(_:)), keyEquivalent: "")
        item.target = self
        menu.insertItem(item, at: 0)
        menu.insertItem(.separator(), at: 1)
        return menu
    }

    @objc func insertDivider(_ sender: Any?) {
        let ns = string as NSString
        let selection = selectedRange()
        let lineRange = ns.lineRange(for: NSRange(location: selection.location, length: 0))
        // Put the divider on its own line after the current one.
        let insertAt = selection.length > 0 ? selection.location : NSMaxRange(lineRange)
        let needsLeadingNewline = insertAt > 0 && ns.character(at: insertAt - 1) != 10
        let text = (needsLeadingNewline ? "\n" : "") + Script.dividerLine + "\n"
        if shouldChangeText(in: NSRange(location: insertAt, length: 0), replacementString: text) {
            replaceCharacters(in: NSRange(location: insertAt, length: 0), with: text)
            didChangeText()
            setSelectedRange(NSRange(location: insertAt + (text as NSString).length, length: 0))
        }
    }
}

struct ScriptEditor: NSViewRepresentable {
    @Binding var text: String

    static let font = NSFont.monospacedSystemFont(ofSize: 15, weight: .regular)

    func makeCoordinator() -> Coordinator { Coordinator(text: $text) }

    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSScrollView()
        scroll.hasVerticalScroller = true
        scroll.drawsBackground = false
        scroll.borderType = .noBorder

        let textView = ScriptTextView()
        textView.delegate = context.coordinator
        textView.isRichText = false
        textView.allowsUndo = true
        textView.drawsBackground = false
        textView.font = Self.font
        textView.textColor = .labelColor
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.isVerticallyResizable = true
        textView.autoresizingMask = [.width]
        textView.textContainer?.widthTracksTextView = true
        textView.textContainerInset = NSSize(width: 0, height: 8)
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineSpacing = 6
        textView.defaultParagraphStyle = paragraph
        textView.typingAttributes = [.font: Self.font, .foregroundColor: NSColor.labelColor, .paragraphStyle: paragraph]
        textView.string = text
        textView.setAccessibilityIdentifier("editor.body")
        scroll.documentView = textView
        context.coordinator.textView = textView
        context.coordinator.restyle()
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        guard let textView = context.coordinator.textView, textView.string != text else { return }
        textView.string = text
        context.coordinator.restyle()
    }

    @MainActor
    final class Coordinator: NSObject, NSTextViewDelegate {
        var text: Binding<String>
        weak var textView: ScriptTextView?

        init(text: Binding<String>) { self.text = text }

        func textDidChange(_ notification: Notification) {
            guard let textView else { return }
            text.wrappedValue = textView.string
            restyle()
        }

        /// Dims divider lines so sections stand out without leaving plain text.
        func restyle() {
            guard let textView, let storage = textView.textStorage else { return }
            let ns = storage.string as NSString
            storage.beginEditing()
            storage.addAttribute(.foregroundColor, value: NSColor.labelColor, range: NSRange(location: 0, length: ns.length))
            ns.enumerateSubstrings(in: NSRange(location: 0, length: ns.length), options: .byLines) { line, range, _, _ in
                guard let line, Script.dividerName(in: line) != nil else { return }
                storage.addAttribute(.foregroundColor, value: NSColor.tertiaryLabelColor, range: range)
            }
            storage.endEditing()
        }
    }
}
