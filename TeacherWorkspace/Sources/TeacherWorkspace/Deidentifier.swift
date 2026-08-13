import Foundation

/// One thing that was taken out, for the consent sheet's "what was removed"
/// list. Occurrences of the same token collapse into a single row with a count
/// — a teacher wants to know their student's name went, not that it went nine
/// times.
struct Redaction: Equatable, Identifiable {
    var id: String { "\(kind?.rawValue ?? patternLabel ?? "?")|\(original)" }
    var kind: PIIToken.Kind?
    /// Set for pattern scrubs (email, phone, path), which have no lexicon kind.
    var patternLabel: String?
    var original: String
    var replacement: String
    var count: Int

    /// How the sheet titles this row.
    var sourceLabel: String { kind?.label ?? patternLabel ?? "something identifying" }
}

/// Deterministic de-identification. No model is involved and none can be: the
/// point of this file is that its output is a function of its input, so the
/// probe in `App.swift` can assert the same thing on every build that a
/// teacher is promised on screen.
enum Deidentifier {

    struct Result {
        var text: String
        /// Substitutions that were made.
        var redactions: [Redaction]
        /// Matches deliberately left alone — first names that are also ordinary
        /// words. Reported to the teacher, never silently replaced.
        var flagged: [Redaction]
    }

    /// Patterns run first so `/Users/dana/plans.md` becomes a file path rather
    /// than a path with the teacher's first name picked out of the middle of it.
    static func process(_ raw: String, lexicon: PIILexicon) -> Result {
        let normalized = PIILexicon.normalize(raw)
        let scrubbed = scrubPatterns(normalized)
        let redacted = redact(scrubbed.text, lexicon: lexicon)
        return Result(text: redacted.text,
                      redactions: merge(scrubbed.redactions + redacted.redactions),
                      flagged: merge(redacted.flagged))
    }

    // MARK: - Lexicon substitution

    static func redact(_ text: String, lexicon: PIILexicon)
        -> (text: String, redactions: [Redaction], flagged: [Redaction]) {
        let matches = lexicon.matches(in: text)
        guard !matches.isEmpty else { return (text, [], []) }

        let ns = text as NSString
        var out = ""
        var cursor = 0
        var redactions: [Redaction] = []
        var flagged: [Redaction] = []

        for match in matches {
            guard match.range.location >= cursor else { continue }
            out += ns.substring(with: NSRange(location: cursor,
                                              length: match.range.location - cursor))
            let original = ns.substring(with: match.range)

            if match.token.isCommonWord {
                // Left in place on purpose. Replacing every "Grace" in a plan
                // about grace periods would make the payload unreadable, and a
                // teacher reading the sheet can judge this one instance in a
                // way a substring match never could.
                out += original
                flagged.append(Redaction(kind: match.token.kind, patternLabel: nil,
                                         original: original, replacement: original, count: 1))
            } else {
                let replacement = lexicon.replacement(for: match.token) + possessiveTail(of: original)
                out += replacement
                redactions.append(Redaction(kind: match.token.kind, patternLabel: nil,
                                            original: original, replacement: replacement, count: 1))
            }
            cursor = match.range.location + match.range.length
        }
        out += ns.substring(from: cursor)
        return (out, redactions, flagged)
    }

    /// "Maya's" becomes "Student A's", not "Student A". The teacher reads this
    /// payload before approving it, so it has to read like English.
    private static func possessiveTail(of original: String) -> String {
        let lowered = original.lowercased()
        if lowered.hasSuffix("'s") || lowered.hasSuffix("\u{2019}s") { return "'s" }
        return ""
    }

    // MARK: - Pattern scrubbing

    /// What the roster can't tell us: contact details, ID numbers, and the
    /// home-directory path that would carry the teacher's account name out with
    /// an attached file. `WorkDocument` already guards the last one for Skill
    /// Check — same leak, same answer.
    static func scrubPatterns(_ text: String) -> (text: String, redactions: [Redaction]) {
        var out = text
        var redactions: [Redaction] = []
        for rule in patternRules {
            let result = apply(rule, to: out)
            out = result.text
            redactions += result.redactions
        }
        return (out, redactions)
    }

    private struct PatternRule {
        var label: String
        var pattern: String
        var replacement: String
    }

    private static let patternRules: [PatternRule] = [
        PatternRule(label: "a file path",
                    pattern: #"/Users/[^/\s]+"#,
                    replacement: "[file path]"),
        PatternRule(label: "an email address",
                    pattern: #"[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}"#,
                    replacement: "[email]"),
        PatternRule(label: "a phone number",
                    pattern: #"(?<![\d-])(\+?\d{1,2}[ .-]?)?\(?\d{3}\)?[ .-]?\d{3}[ .-]?\d{4}(?![\d-])"#,
                    replacement: "[phone]"),
        // Six digits or more in a row: a student ID, a lunch number, an SSN.
        // Page ranges and years are shorter, so ordinary plans survive intact.
        PatternRule(label: "an ID number",
                    pattern: #"(?<![\d-])\d{6,}(?![\d-])"#,
                    replacement: "[id number]"),
    ]

    private static func apply(_ rule: PatternRule, to text: String)
        -> (text: String, redactions: [Redaction]) {
        guard let regex = try? NSRegularExpression(pattern: rule.pattern) else { return (text, []) }
        let ns = text as NSString
        let matches = regex.matches(in: text, range: NSRange(location: 0, length: ns.length))
        guard !matches.isEmpty else { return (text, []) }

        var out = ""
        var cursor = 0
        var redactions: [Redaction] = []
        for match in matches {
            guard match.range.location >= cursor else { continue }
            out += ns.substring(with: NSRange(location: cursor,
                                              length: match.range.location - cursor))
            out += rule.replacement
            redactions.append(Redaction(kind: nil, patternLabel: rule.label,
                                        original: ns.substring(with: match.range),
                                        replacement: rule.replacement, count: 1))
            cursor = match.range.location + match.range.length
        }
        out += ns.substring(from: cursor)
        return (out, redactions)
    }

    // MARK: - Reporting

    /// Collapse repeats so the sheet shows one row per thing removed.
    static func merge(_ redactions: [Redaction]) -> [Redaction] {
        var order: [String] = []
        var byKey: [String: Redaction] = [:]
        for item in redactions {
            if var existing = byKey[item.id] {
                existing.count += item.count
                byKey[item.id] = existing
            } else {
                order.append(item.id)
                byKey[item.id] = item
            }
        }
        return order.compactMap { byKey[$0] }
    }
}
