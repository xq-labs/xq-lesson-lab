import Foundation
import NaturalLanguage

/// The hard block between a de-identified payload and the network.
///
/// `Deidentifier` does the work; this re-checks it. The separation matters:
/// the gate runs twice, once when a `ReviewPayload` is constructed and again
/// on the exact bytes handed to `URLSession`, so an edit the teacher made in
/// the consent sheet after the redaction pass is still caught. A payload that
/// would leak a known name cannot be built, and if one somehow is, it cannot
/// be sent.
enum RedactionGate {

    struct Finding: Equatable, Identifiable {
        var id: String { "\(kind)|\(offset)" }

        enum Kind: Equatable {
            /// A name, school or class the app knows from My Classroom.
            case lexicon(PIIToken.Kind)
            case email, phone, idNumber, homePath
            /// A first name that is also an ordinary word, left in place.
            case commonWordName(PIIToken.Kind)
            /// Something that looks like a person's name but isn't on the
            /// roster — a classmate quoted in a portfolio, a parent named in a
            /// family email.
            case unrecognizedPersonName
        }

        var kind: Kind
        /// UTF-16 offset into the checked text, for ordering the sheet's rows.
        var offset: Int

        /// Blocking findings stop the send. Advisory ones are shown to the
        /// teacher, who is in a far better position to judge them than a
        /// substring match is — blocking on every `NLTagger` false positive
        /// would make the feature unusable, and hiding them would be dishonest.
        var isBlocking: Bool {
            switch kind {
            case .lexicon, .email, .phone, .idNumber, .homePath: return true
            case .commonWordName, .unrecognizedPersonName: return false
            }
        }

        /// Named by kind, never by the matched text. The sheet must not echo a
        /// student's name into a second place on screen just to say it found it.
        var message: String {
            switch kind {
            case .lexicon(let k): return "This still contains \(k.label)."
            case .email: return "This still contains an email address."
            case .phone: return "This still contains a phone number."
            case .idNumber: return "This still contains a long number that could be an ID."
            case .homePath: return "This still contains a file path from your Mac."
            case .commonWordName(let k):
                return "\(k.label.capitalizedFirst) is also an ordinary word, so it was left as-is — check it reads the way you want."
            case .unrecognizedPersonName:
                return "This looks like a person's name the app doesn't recognise from your roster."
            }
        }
    }

    /// Thrown when a payload would carry something the gate blocks. Callers
    /// surface `findings`; nothing here ever puts the matched text in an error
    /// message, which would only move the leak into a log line.
    struct Blocked: LocalizedError {
        var findings: [Finding]
        var errorDescription: String? {
            "Not sent. The check found something that looks like a student's name."
        }
    }

    // MARK: - Verification

    static func verify(_ text: String, lexicon: PIILexicon) -> [Finding] {
        let normalized = PIILexicon.normalize(text)
        var findings: [Finding] = []

        for match in lexicon.matches(in: normalized) {
            findings.append(Finding(
                kind: match.token.isCommonWord
                    ? .commonWordName(match.token.kind)
                    : .lexicon(match.token.kind),
                offset: match.range.location))
        }
        findings += patternFindings(in: normalized)
        findings += strangerNameFindings(in: normalized, lexicon: lexicon)
        return findings.sorted { $0.offset < $1.offset }
    }

    /// The last check before the bytes go out. Runs on the serialized request
    /// body itself rather than on the string it was built from — whatever else
    /// changed in between, this sees what `URLSession` sees.
    static func assertClean(_ data: Data, lexicon: PIILexicon) throws {
        let text = String(decoding: data, as: UTF8.self)
        let blocking = verify(text, lexicon: lexicon).filter(\.isBlocking)
        guard blocking.isEmpty else { throw Blocked(findings: blocking) }
    }

    static func assertClean(_ text: String, lexicon: PIILexicon) throws {
        try assertClean(Data(text.utf8), lexicon: lexicon)
    }

    // MARK: - Patterns

    private static let patterns: [(Finding.Kind, String)] = [
        (.homePath, #"/Users/[^/\s]+"#),
        (.email, #"[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}"#),
        (.phone, #"(?<![\d-])(\+?\d{1,2}[ .-]?)?\(?\d{3}\)?[ .-]?\d{3}[ .-]?\d{4}(?![\d-])"#),
        (.idNumber, #"(?<![\d-])\d{6,}(?![\d-])"#),
    ]

    private static func patternFindings(in text: String) -> [Finding] {
        let ns = text as NSString
        var out: [Finding] = []
        for (kind, pattern) in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern) else { continue }
            for match in regex.matches(in: text, range: NSRange(location: 0, length: ns.length)) {
                out.append(Finding(kind: kind, offset: match.range.location))
            }
        }
        return out
    }

    // MARK: - Names the roster doesn't know

    /// Advisory only. `NLTagger` finds personal names the lexicon can't — but
    /// it also finds "Bunsen" and "Mendel", so this informs the teacher rather
    /// than stopping them.
    private static func strangerNameFindings(in text: String, lexicon: PIILexicon) -> [Finding] {
        let known = Set(lexicon.tokens.map { PIILexicon.fold($0.text) })
        let pseudonyms = Set(lexicon.pseudonyms.values.map(PIILexicon.fold))
        let tagger = NLTagger(tagSchemes: [.nameType])
        tagger.string = text

        var out: [Finding] = []
        let options: NLTagger.Options = [.omitPunctuation, .omitWhitespace, .joinNames]
        tagger.enumerateTags(in: text.startIndex..<text.endIndex, unit: .word,
                             scheme: .nameType, options: options) { tag, range in
            guard tag == .personalName else { return true }
            let name = String(text[range])
            let folded = PIILexicon.fold(name)
            guard !known.contains(folded), !pseudonyms.contains(folded) else { return true }
            // "Student A" and friends tokenize as a personal name; so does the
            // teacher's own placeholder. Neither is a leak.
            guard !folded.hasPrefix("student "), !folded.hasPrefix("[") else { return true }
            let offset = text.distance(from: text.startIndex, to: range.lowerBound)
            out.append(Finding(kind: .unrecognizedPersonName, offset: offset))
            return true
        }
        return out
    }
}

extension String {
    /// Sentence-case for a phrase that starts a sentence ("your name" ->
    /// "Your name"). `capitalized` would title-case the whole thing.
    var capitalizedFirst: String {
        guard let first else { return self }
        return String(first).uppercased() + dropFirst()
    }
}
