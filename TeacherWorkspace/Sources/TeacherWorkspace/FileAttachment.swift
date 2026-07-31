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
        .pdf, .plainText, .utf8PlainText, .text, .commaSeparatedText,
        .tabSeparatedText, .rtf, UTType("net.daringfireball.markdown") ?? .plainText,
    ]

    /// Extracts readable text from a file. Returns nil when the format has
    /// no extractable text.
    static func extractText(from url: URL) -> String? {
        let ext = url.pathExtension.lowercased()
        var raw: String?
        if ext == "pdf" {
            raw = PDFDocument(url: url)?.string
        } else if ext == "rtf" || ext == "rtfd" {
            if let data = try? Data(contentsOf: url),
               let attributed = try? NSAttributedString(
                data: data,
                options: [.documentType: NSAttributedString.DocumentType.rtf],
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
