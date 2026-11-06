import AppKit
import PDFKit
import UniformTypeIdentifiers

/// Turns files into notes and notes into files.
enum NoteTransfer {
    struct ImportedNote: Equatable {
        let title: String
        let body: String
    }

    enum TransferError: LocalizedError {
        case unsupported(String)
        case unreadable(String)

        var errorDescription: String? {
            switch self {
            case .unsupported(let name): "Vaasi can't open “\(name)”. Try Markdown, text, RTF, Word, HTML, or PDF."
            case .unreadable(let name): "“\(name)” couldn't be read."
            }
        }
    }

    static let markdown = UTType("net.daringfireball.markdown") ?? UTType(filenameExtension: "md", conformingTo: .plainText)!
    static let docx = UTType("org.openxmlformats.wordprocessingml.document") ?? UTType(filenameExtension: "docx")!

    static let importableTypes: [UTType] = [markdown, .plainText, .rtf, .rtfd, docx, .html, .pdf]

    static func importNote(from url: URL) throws -> ImportedNote {
        let name = url.lastPathComponent
        let fallbackTitle = url.deletingPathExtension().lastPathComponent
        let type = UTType(filenameExtension: url.pathExtension.lowercased())

        let text: String
        if type == markdown || url.pathExtension.lowercased() == "md" || url.pathExtension.lowercased() == "markdown" {
            text = try readText(url, name: name)
            return markdownNote(text, fallbackTitle: fallbackTitle)
        } else if type == .pdf {
            guard let document = PDFDocument(url: url), let string = document.string else { throw TransferError.unreadable(name) }
            text = string
        } else if type?.conforms(to: .plainText) == true && type?.conforms(to: .html) != true && type?.conforms(to: .rtf) != true {
            text = try readText(url, name: name)
        } else if let documentType = documentType(for: type) {
            let options: [NSAttributedString.DocumentReadingOptionKey: Any] = [.documentType: documentType]
            guard let attributed = try? NSAttributedString(url: url, options: options, documentAttributes: nil) else {
                throw TransferError.unreadable(name)
            }
            text = attributed.string
        } else {
            throw TransferError.unsupported(name)
        }
        return ImportedNote(title: fallbackTitle, body: tidy(text))
    }

    private static func documentType(for type: UTType?) -> NSAttributedString.DocumentType? {
        guard let type else { return nil }
        if type.conforms(to: .rtfd) { return .rtfd }
        if type.conforms(to: .rtf) { return .rtf }
        if type.conforms(to: .html) { return .html }
        if type == docx { return .officeOpenXML }
        return nil
    }

    private static func readText(_ url: URL, name: String) throws -> String {
        if let text = try? String(contentsOf: url, encoding: .utf8) { return text }
        var encoding = String.Encoding.utf8
        if let text = try? String(contentsOf: url, usedEncoding: &encoding) { return text }
        throw TransferError.unreadable(name)
    }

    /// A leading `# Heading` becomes the title.
    private static func markdownNote(_ text: String, fallbackTitle: String) -> ImportedNote {
        var lines = text.replacingOccurrences(of: "\r\n", with: "\n").components(separatedBy: "\n")
        while let first = lines.first, first.trimmingCharacters(in: .whitespaces).isEmpty { lines.removeFirst() }
        if let first = lines.first, first.hasPrefix("# ") {
            lines.removeFirst()
            return ImportedNote(title: String(first.dropFirst(2)).trimmingCharacters(in: .whitespaces),
                                body: tidy(lines.joined(separator: "\n")))
        }
        return ImportedNote(title: fallbackTitle, body: tidy(lines.joined(separator: "\n")))
    }

    private static func tidy(_ text: String) -> String {
        text.replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .replacingOccurrences(of: "\u{2028}", with: "\n")
            .replacingOccurrences(of: "\u{00A0}", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: Export

    enum ExportFormat: String, CaseIterable, Identifiable {
        case markdown, plainText, rtf, docx, html, pdf

        var id: String { rawValue }

        var title: String {
            switch self {
            case .markdown: "Markdown"
            case .plainText: "Plain Text"
            case .rtf: "Rich Text (RTF)"
            case .docx: "Word (DOCX)"
            case .html: "HTML"
            case .pdf: "PDF"
            }
        }

        var contentType: UTType {
            switch self {
            case .markdown: NoteTransfer.markdown
            case .plainText: .plainText
            case .rtf: .rtf
            case .docx: NoteTransfer.docx
            case .html: .html
            case .pdf: .pdf
            }
        }

        var fileExtension: String {
            switch self {
            case .markdown: "md"
            case .plainText: "txt"
            case .rtf: "rtf"
            case .docx: "docx"
            case .html: "html"
            case .pdf: "pdf"
            }
        }
    }

    static func exportData(title: String, body: String, format: ExportFormat) throws -> Data {
        switch format {
        case .markdown:
            return Data("# \(title)\n\n\(body)\n".utf8)
        case .plainText:
            return Data("\(title)\n\n\(body)\n".utf8)
        case .rtf, .docx, .html:
            let document = attributedDocument(title: title, body: body)
            let type: NSAttributedString.DocumentType = format == .rtf ? .rtf : format == .docx ? .officeOpenXML : .html
            return try document.data(from: NSRange(location: 0, length: document.length),
                                     documentAttributes: [.documentType: type, .title: title])
        case .pdf:
            return pdfData(attributedDocument(title: title, body: body))
        }
    }

    private static func attributedDocument(title: String, body: String) -> NSAttributedString {
        let result = NSMutableAttributedString(string: title + "\n\n", attributes: [
            .font: NSFont.systemFont(ofSize: 24, weight: .semibold), .foregroundColor: NSColor.black,
        ])
        result.append(NSAttributedString(string: body, attributes: [
            .font: NSFont.monospacedSystemFont(ofSize: 12, weight: .regular), .foregroundColor: NSColor.black,
        ]))
        return result
    }

    /// Paginated US Letter PDF.
    private static func pdfData(_ text: NSAttributedString) -> Data {
        let data = NSMutableData()
        var mediaBox = CGRect(x: 0, y: 0, width: 612, height: 792)
        guard let consumer = CGDataConsumer(data: data as CFMutableData),
              let context = CGContext(consumer: consumer, mediaBox: &mediaBox, nil) else { return Data() }
        let framesetter = CTFramesetterCreateWithAttributedString(text)
        let textRect = mediaBox.insetBy(dx: 54, dy: 54)
        var location = 0
        repeat {
            context.beginPDFPage(nil)
            let path = CGPath(rect: textRect, transform: nil)
            let frame = CTFramesetterCreateFrame(framesetter, CFRange(location: location, length: 0), path, nil)
            CTFrameDraw(frame, context)
            let visible = CTFrameGetVisibleStringRange(frame)
            location += max(1, visible.length)
            context.endPDFPage()
        } while location < text.length
        context.closePDF()
        return data as Data
    }
}
