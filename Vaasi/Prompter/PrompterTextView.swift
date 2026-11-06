import AppKit
import SwiftUI

/// Appearance of the scrolling text.
struct PrompterTextStyle: Equatable {
    var font: PrompterFont
    var size: Double
    var lineSpacing: Double
    var colorHex: String
}

/// A non-editable text view the prompter scrolls by setting its offset every
/// frame. Native layout keeps long scripts smooth, and trackpad scrolling works
/// for free.
final class PrompterTextHost: NSScrollView {
    private let textView = NSTextView()
    private var isSettingOffset = false
    private var lastLaidOut: (text: String, style: PrompterTextStyle, width: CGFloat)?

    /// The user scrolled with the trackpad or mouse.
    var onUserScroll: ((Double) -> Void)?
    /// Content height or viewport changed: the new maximum offset.
    var onLayout: ((Double) -> Void)?

    /// Where the line being read sits, from the top of the viewport.
    var readingLine: CGFloat { max(8, bounds.height * 0.22) }

    override init(frame: NSRect) {
        super.init(frame: frame)
        drawsBackground = false
        hasVerticalScroller = false
        hasHorizontalScroller = false
        verticalScrollElasticity = .none
        horizontalScrollElasticity = .none
        borderType = .noBorder

        textView.isEditable = false
        textView.isSelectable = false
        textView.drawsBackground = false
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.textContainer?.widthTracksTextView = true
        textView.textContainer?.lineFragmentPadding = 0
        textView.setAccessibilityIdentifier("prompter.text")
        documentView = textView

        contentView.postsBoundsChangedNotifications = true
        NotificationCenter.default.addObserver(self, selector: #selector(boundsChanged),
                                               name: NSView.boundsDidChangeNotification, object: contentView)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    func configure(text: String, style: PrompterTextStyle) {
        let width = bounds.width
        if let last = lastLaidOut, last.text == text, last.style == style, last.width == width { return }
        lastLaidOut = (text, style, width)

        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .center
        paragraph.lineSpacing = style.lineSpacing
        paragraph.paragraphSpacing = style.size * 0.5
        let font = style.font.nsFont(size: style.size)
        let color = NSColor(hex: style.colorHex) ?? .white

        let content = NSMutableAttributedString(string: text, attributes: [
            .font: font, .foregroundColor: color, .paragraphStyle: paragraph,
        ])
        // End-of-text marker so you can see the script is about to finish.
        content.append(NSAttributedString(string: "\n\n• • •", attributes: [
            .font: NSFont.systemFont(ofSize: style.size * 0.7, weight: .semibold),
            .foregroundColor: color.withAlphaComponent(0.35),
            .paragraphStyle: paragraph,
        ]))
        textView.textStorage?.setAttributedString(content)
        updateInsets()
    }

    override func layout() {
        super.layout()
        updateInsets()
    }

    private func updateInsets() {
        guard let container = textView.textContainer, let layoutManager = textView.layoutManager else { return }
        // Text starts on the reading line and can scroll until its end reaches it.
        let top = readingLine
        let bottom = max(0, bounds.height - readingLine - 40)
        textView.textContainerInset = NSSize(width: 0, height: 0)
        textView.frame.size.width = contentView.bounds.width
        container.size = NSSize(width: contentView.bounds.width, height: .greatestFiniteMagnitude)
        layoutManager.ensureLayout(for: container)
        let used = layoutManager.usedRect(for: container).height
        textView.textContainerInset = NSSize(width: 0, height: top)
        let docHeight = top + used + bottom
        textView.frame.size.height = max(docHeight, bounds.height)
        onLayout?(max(0, docHeight - bounds.height))
    }

    var offset: Double { Double(contentView.bounds.origin.y) }

    func setOffset(_ value: Double) {
        guard abs(Double(contentView.bounds.origin.y) - value) > 0.01 else { return }
        isSettingOffset = true
        contentView.scroll(to: NSPoint(x: 0, y: value))
        reflectScrolledClipView(contentView)
        isSettingOffset = false
    }

    @objc private func boundsChanged() {
        guard !isSettingOffset else { return }
        onUserScroll?(offset)
    }

    /// Scroll offset that puts the given text range on the reading line.
    func offset(forCharacterRange range: NSRange) -> Double? {
        guard let layoutManager = textView.layoutManager, let container = textView.textContainer,
              range.location < (textView.string as NSString).length else { return nil }
        let glyphs = layoutManager.glyphRange(forCharacterRange: range, actualCharacterRange: nil)
        let rect = layoutManager.boundingRect(forGlyphRange: glyphs, in: container)
        return Double(rect.minY + textView.textContainerInset.height - readingLine)
    }

    /// Character index on the reading line at the given offset.
    func characterIndex(atOffset offset: Double) -> Int {
        guard let layoutManager = textView.layoutManager, let container = textView.textContainer else { return 0 }
        let point = NSPoint(x: container.size.width / 2, y: offset)
        return layoutManager.characterIndex(for: point, in: container, fractionOfDistanceBetweenInsertionPoints: nil)
    }

    /// Height of one line, for line-by-line stepping.
    var lineHeight: Double {
        guard let font = textView.textStorage?.attribute(.font, at: 0, effectiveRange: nil) as? NSFont else { return 30 }
        return Double(font.ascender - font.descender + font.leading) + Double(lastLaidOut?.style.lineSpacing ?? 0)
    }
}

struct PrompterTextView: NSViewRepresentable {
    let text: String
    let style: PrompterTextStyle
    let controller: PrompterController

    func makeNSView(context: Context) -> PrompterTextHost {
        let host = PrompterTextHost(frame: .zero)
        controller.attach(textHost: host)
        return host
    }

    func updateNSView(_ host: PrompterTextHost, context: Context) {
        host.configure(text: text, style: style)
    }
}
