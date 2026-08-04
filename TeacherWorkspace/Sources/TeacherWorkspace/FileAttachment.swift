import Foundation
import PDFKit
import UniformTypeIdentifiers

/// A file (or referenced artifact) queued in the composer, to be sent with
/// the next message. Text is extracted on-device — nothing is uploaded.
struct PendingAttachment: Identifiable, Equatable {
    let id = UUID()
    var name: String
    var text: String
}

enum FileAttachment {
    /// Keep attachments small enough for the 2B model's 8K context.
    static let maxCharacters = 6000

    static let allowedTypes: [UTType] = [
        .pdf, .plainText, .utf8PlainText, .text, .commaSeparatedText, .tabSeparatedText, .rtf,
    ] + [
        "net.daringfireball.markdown",
        "org.openxmlformats.wordprocessingml.document",  // .docx
        "com.microsoft.word.doc",                        // .doc
        "org.oasis-open.opendocument.text",              // .odt
    ].compactMap(UTType.init)

    /// Word processor formats AppKit reads on its own — it understands the
    /// containers, so there's no ZIP handling here.
    private static let attributedTypes: [String: NSAttributedString.DocumentType] = [
        "rtf": .rtf, "rtfd": .rtf,
        "docx": .officeOpenXML, "doc": .docFormat, "odt": .openDocument,
    ]

    /// Extracts readable text from a file. Returns nil when the format has
    /// no extractable text — a scan with no text layer reaches here as an
    /// empty string, so callers must treat nil as "tell the teacher", not
    /// "nothing happened".
    static func extractText(from url: URL) -> String? {
        let ext = url.pathExtension.lowercased()
        var raw: String?
        if ext == "pdf" {
            raw = PDFDocument(url: url)?.string
        } else if let documentType = attributedTypes[ext] {
            if let data = try? Data(contentsOf: url),
               let attributed = try? NSAttributedString(
                data: data,
                options: [.documentType: documentType],
                documentAttributes: nil) {
                raw = attributed.string
            }
        } else {
            raw = (try? String(contentsOf: url, encoding: .utf8))
                ?? (try? String(contentsOf: url, encoding: .isoLatin1))
        }
        guard var text = raw?.trimmingCharacters(in: .whitespacesAndNewlines),
              !text.isEmpty else { return nil }
        if text.count > maxCharacters {
            text = String(text.prefix(maxCharacters)) + "\n…[truncated for length]"
        }
        return text
    }

    static func attachment(from url: URL) -> PendingAttachment? {
        guard let text = extractText(from: url) else { return nil }
        return PendingAttachment(name: url.lastPathComponent, text: text)
    }
}
