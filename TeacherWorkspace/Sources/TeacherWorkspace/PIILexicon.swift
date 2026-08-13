import Foundation

/// One piece of text the app knows to be identifying, because the teacher
/// typed it into My Classroom themselves.
///
/// This is the whole trick behind the frontier-review gate: the app is not
/// guessing at what might be a name. It has the roster, so it has an exact
/// list, and an exact list can be checked deterministically. A model-based
/// redactor can only ever say "probably".
struct PIIToken: Equatable {
    enum Kind: String, Codable {
        case studentName, studentNameComponent
        case teacherName, teacherNameComponent
        case school, className

        /// What a match becomes when it isn't a student (students get a
        /// pseudonym from the lexicon instead).
        var placeholder: String {
            switch self {
            case .studentName, .studentNameComponent: return "[student]"
            case .teacherName, .teacherNameComponent: return "[teacher]"
            case .school: return "[school]"
            case .className: return "[class]"
            }
        }

        /// For the consent sheet, which names findings by kind rather than
        /// echoing the matched text into a second place on screen.
        var label: String {
            switch self {
            case .studentName, .studentNameComponent: return "a student's name"
            case .teacherName, .teacherNameComponent: return "your name"
            case .school: return "your school"
            case .className: return "a class name"
            }
        }
    }

    var kind: Kind
    var text: String
    /// `Student.id.uuidString`, when this token belongs to exactly one student.
    /// Nil for a component two students share — "Maya" on a roster with two
    /// Mayas can't be pseudonymised, so it falls back to `[student]`.
    var studentId: String?
    /// A first name that is also an ordinary English word ("Grace", "May").
    /// Substituting these blind shreds normal prose, so they are reported to
    /// the teacher and left in place. See `PIILexicon.commonWords`.
    var isCommonWord = false
}

/// Every identifying token the app knows about, ready to scan text with.
struct PIILexicon {
    /// Longest-first, so "Maya Rodriguez" wins over "Maya" at the same offset.
    /// Same ordering rule as `MentionScanner.sorted`.
    var tokens: [PIIToken] = []
    /// `Student.id.uuidString` -> "Student A".
    var pseudonyms: [String: String] = [:]
    /// The sorted student ids the pseudonyms were assigned from. Stored on a
    /// saved review so the mapping can be rebuilt later for display without
    /// ever writing the reverse map (a name beside its pseudonym) to disk.
    var studentIdOrder: [String] = []

    struct Match: Equatable {
        var range: NSRange
        var token: PIIToken
    }

    /// Components shorter than this are too collision-prone to scan for — a
    /// student called "Jo" would redact every "jo" in the document.
    static let minimumComponentLength = 3

    /// First names that are also ordinary words. Matched and reported, never
    /// substituted automatically.
    static let commonWords: Set<String> = [
        "grace", "hope", "may", "art", "sky", "rain", "dawn", "faith", "joy",
        "summer", "autumn", "april", "june", "july", "august", "sunny", "star",
        "rose", "lily", "ivy", "daisy", "jasmine", "violet", "olive", "sage",
        "hunter", "chase", "will", "mark", "bill", "rob", "drew", "frank",
        "earl", "reed", "cliff", "dale", "glen", "ray", "van", "king", "young",
        "love", "angel", "prince", "noble", "rich", "gay", "moon", "river",
        "brook", "forest", "stone", "wood", "field", "hill", "banks", "price",
        "case", "long", "short", "white", "black", "brown", "green", "gray",
        "grey", "best", "day", "week", "north", "south", "east", "west",
    ]

    // MARK: - Building

    static func build(from classroom: Classroom) -> PIILexicon {
        var lexicon = PIILexicon()

        let students = classroom.classes.flatMap(\.students).filter { !$0.name.isEmpty }
        lexicon.studentIdOrder = students.map(\.id.uuidString).sorted()
        lexicon.pseudonyms = Self.pseudonyms(forStudentIds: lexicon.studentIdOrder)

        var tokens: [PIIToken] = []

        // Full student names first, then their components. A component shared
        // by two students loses its pseudonym: the app can't tell which one a
        // bare "Rodriguez" means, so it redacts generically rather than
        // guessing and quietly attributing work to the wrong child.
        var componentOwners: [String: Set<String>] = [:]
        for student in students {
            let name = normalize(student.name)
            tokens.append(PIIToken(kind: .studentName, text: name, studentId: student.id.uuidString))
            for part in components(of: name) {
                componentOwners[fold(part), default: []].insert(student.id.uuidString)
            }
        }
        for student in students {
            for part in components(of: normalize(student.name)) {
                let owners = componentOwners[fold(part)] ?? []
                guard owners.first == student.id.uuidString || owners.count > 1 else { continue }
                // Emit a shared component once, from whichever student sorts
                // first — `dedupe` collapses the rest anyway.
                tokens.append(PIIToken(kind: .studentNameComponent, text: part,
                                       studentId: owners.count == 1 ? student.id.uuidString : nil,
                                       isCommonWord: commonWords.contains(fold(part))))
            }
        }

        if !classroom.teacherName.isEmpty {
            let name = normalize(classroom.teacherName)
            tokens.append(PIIToken(kind: .teacherName, text: name, studentId: nil))
            for part in components(of: name) {
                tokens.append(PIIToken(kind: .teacherNameComponent, text: part, studentId: nil,
                                       isCommonWord: commonWords.contains(fold(part))))
            }
        }
        if !classroom.school.isEmpty {
            tokens.append(PIIToken(kind: .school, text: normalize(classroom.school), studentId: nil))
        }
        for section in classroom.classes where !section.name.isEmpty {
            tokens.append(PIIToken(kind: .className, text: normalize(section.name), studentId: nil))
        }

        lexicon.tokens = dedupe(tokens).sorted { $0.text.count > $1.text.count }
        return lexicon
    }

    /// Deterministic from the sorted id list, so a review saved months ago
    /// still renders "Student A" as the same child — and so the app never has
    /// to persist a name-to-pseudonym table beside the de-identified text.
    static func pseudonyms(forStudentIds ids: [String]) -> [String: String] {
        var out: [String: String] = [:]
        for (index, id) in ids.enumerated() {
            out[id] = "Student \(letters(for: index))"
        }
        return out
    }

    /// A, B, … Z, AA, AB — spreadsheet-column style, so a 40-student roster
    /// doesn't run out.
    private static func letters(for index: Int) -> String {
        var n = index
        var out = ""
        repeat {
            out = String(UnicodeScalar(65 + n % 26)!) + out
            n = n / 26 - 1
        } while n >= 0
        return out
    }

    private static func dedupe(_ tokens: [PIIToken]) -> [PIIToken] {
        var seen = Set<String>()
        var out: [PIIToken] = []
        for token in tokens {
            let key = "\(token.kind.rawValue)|\(fold(token.text))"
            guard seen.insert(key).inserted else { continue }
            out.append(token)
        }
        return out
    }

    private static func components(of name: String) -> [String] {
        name.split(whereSeparator: { $0.isWhitespace || $0 == "-" })
            .map(String.init)
            .filter { $0.count >= minimumComponentLength && $0 != name }
    }

    // MARK: - Text normalisation

    /// Canonically precomposed, so "Sofía" is always five UTF-16 units whether
    /// it was typed, pasted, or read out of a CSV. Every offset this file
    /// produces assumes the text went through here first — decomposed input
    /// would shift ranges out from under the substitution.
    static func normalize(_ text: String) -> String {
        text.precomposedStringWithCanonicalMapping
    }

    /// Case- and diacritic-insensitive comparison key. "Sofia" matches "Sofía",
    /// "maya" matches "Maya".
    static func fold(_ text: String) -> String {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
    }

    // MARK: - Scanning

    /// Every token occurrence in `text`, left to right, longest match wins.
    /// `text` must already be `normalize`d.
    func matches(in text: String) -> [Match] {
        guard !tokens.isEmpty else { return [] }
        let ns = text as NSString
        var out: [Match] = []
        var i = 0
        while i < ns.length {
            guard isWordStart(ns, at: i) else {
                i += 1
                continue
            }
            var advanced = false
            for token in tokens {
                let length = (token.text as NSString).length
                guard i + length <= ns.length else { continue }
                let candidate = ns.substring(with: NSRange(location: i, length: length))
                guard Self.fold(candidate) == Self.fold(token.text) else { continue }
                guard let total = matchLength(ns, at: i, tokenLength: length) else { continue }
                out.append(Match(range: NSRange(location: i, length: total), token: token))
                i += total
                advanced = true
                break
            }
            if !advanced { i += 1 }
        }
        return out
    }

    /// What a match is replaced with. Students become their pseudonym so the
    /// reviewer can still tell two children apart in the text; everything else
    /// becomes a generic placeholder.
    func replacement(for token: PIIToken) -> String {
        if let id = token.studentId, let pseudonym = pseudonyms[id] { return pseudonym }
        return token.kind.placeholder
    }

    /// A token only starts at a word boundary, so "Maya" doesn't fire inside
    /// "Amaya". Same rule as `MentionScanner.isBoundary`, applied to the name
    /// itself rather than to a leading `@`.
    private func isWordStart(_ ns: NSString, at index: Int) -> Bool {
        guard index > 0 else { return true }
        let prev = Character(UnicodeScalar(ns.character(at: index - 1)) ?? " ")
        return !(prev.isLetter || prev.isNumber)
    }

    /// The full length of the match including a possessive tail, or nil if the
    /// token runs into more word — "Maya" must not match inside "Mayapple",
    /// but must match all of "Maya's" and "Mayas".
    private func matchLength(_ ns: NSString, at index: Int, tokenLength: Int) -> Int? {
        let end = index + tokenLength
        guard end < ns.length else { return tokenLength }

        let next = Character(UnicodeScalar(ns.character(at: end)) ?? " ")
        if next == "'" || next == "\u{2019}" {
            guard end + 1 < ns.length else { return tokenLength + 1 }
            let after = Character(UnicodeScalar(ns.character(at: end + 1)) ?? " ")
            if after == "s" || after == "S" { return tokenLength + 2 }
            return tokenLength + 1
        }
        if next == "s" || next == "S" {
            guard end + 1 < ns.length else { return tokenLength + 1 }
            let after = Character(UnicodeScalar(ns.character(at: end + 1)) ?? " ")
            return (after.isLetter || after.isNumber) ? nil : tokenLength + 1
        }
        return (next.isLetter || next.isNumber) ? nil : tokenLength
    }
}
