import Foundation
import NaturalLanguage

/// A piece of student work, split into numbered sentences.
///
/// The numbering is the point. Stages ask the model for a sentence *number*
/// and the app renders the sentence from its own copy, so a citation can't be
/// something the model invented — the worst it can do is point at the wrong
/// real sentence, which a teacher can see for themselves.
struct WorkDocument {
    /// Enough text to be worth judging. A scan with no text layer, or a
    /// one-line answer, produces a confident evaluation of nothing.
    static let minimumCharacters = 200
    static let minimumSentences = 3

    /// Evaluation reads more than the composer does — chat's 6000-character
    /// cap is right for a chat turn and too small for an essay. Stages budget
    /// their own prompts against the context window regardless.
    static let maxCharacters = 24000

    var text: String
    var sentences: [String]
    /// Filename only, never a path — a path leaks /Users/<name>/.
    var sourceName: String?

    enum Rejection: LocalizedError {
        case tooShort(characters: Int)
        case tooFewSentences(count: Int)

        var errorDescription: String? {
            switch self {
            case .tooShort(let characters):
                return "There are only \(characters) characters here — too little to place on a progression. "
                    + "If this came from a scan, paste the text instead."
            case .tooFewSentences(let count):
                return "This is only \(count) sentence\(count == 1 ? "" : "s"). "
                    + "A progression needs more to go on."
            }
        }
    }

    init(text raw: String, sourceName: String? = nil) throws {
        var trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.count > Self.maxCharacters {
            trimmed = String(trimmed.prefix(Self.maxCharacters))
        }
        guard trimmed.count >= Self.minimumCharacters else {
            throw Rejection.tooShort(characters: trimmed.count)
        }
        let split = Self.splitSentences(trimmed)
        guard split.count >= Self.minimumSentences else {
            throw Rejection.tooFewSentences(count: split.count)
        }
        text = trimmed
        sentences = split
        self.sourceName = sourceName
    }

    /// `[1] …` per line, the form every stage prompt shows the model.
    var numbered: String {
        sentences.enumerated()
            .map { "[\($0.offset + 1)] \($0.element)" }
            .joined(separator: "\n")
    }

    /// 1-based, matching what the model is shown. Out of range returns nil so
    /// a bad index becomes "placed without a citation" rather than a crash.
    func sentence(_ number: Int) -> String? {
        guard number >= 1, number <= sentences.count else { return nil }
        return sentences[number - 1]
    }

    private static func splitSentences(_ text: String) -> [String] {
        let tokenizer = NLTokenizer(unit: .sentence)
        tokenizer.string = text
        var out: [String] = []
        tokenizer.enumerateTokens(in: text.startIndex..<text.endIndex) { range, _ in
            let s = text[range].trimmingCharacters(in: .whitespacesAndNewlines)
            if !s.isEmpty { out.append(s) }
            return true
        }
        return out
    }
}
