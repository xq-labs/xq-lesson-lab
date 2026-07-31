import SwiftUI

/// An `@mention` the teacher can drop into the composer: a student, a class,
/// or one of their saved artifacts. Typing `@` offers these; the matched text
/// is tinted in the field, and on send each one expands into a hidden context
/// block so the model sees the actual roster note or rubric, not just a name.
struct Mention: Identifiable, Equatable, Hashable {
    var kind: Kind
    /// Artifact id, or the student/class UUID string.
    var id: String
    /// The text that follows `@` in the field.
    var name: String
    /// Shown dimmed in the picker (class for a student, meta for an artifact).
    var subtitle: String

    enum Kind: String, CaseIterable {
        case student, section, rubric, activity, pog, quiz

        var label: String {
            switch self {
            case .student: return "Students"
            case .section: return "Classes"
            case .rubric: return "Rubrics"
            case .activity: return "Activities"
            case .pog: return "Portraits of a Graduate"
            case .quiz: return "Quizzes"
            }
        }

        var icon: String {
            switch self {
            case .student: return "person"
            case .section: return "person.2"
            case .rubric: return "tablecells"
            case .activity: return "triangle"
            case .pog: return "person.crop.circle"
            case .quiz: return "list.bullet.rectangle"
            }
        }

        /// Artifact kinds map onto a ref so the chat can link them.
        var artifactType: ArtifactType? {
            switch self {
            case .rubric: return .rubric
            case .activity: return .activity
            case .pog: return .pog
            case .quiz: return .quiz
            case .student, .section: return nil
            }
        }
    }
}

enum MentionScanner {
    /// Longest-name-first so "@Maya Rodriguez" wins over a hypothetical "@Maya".
    static func sorted(_ catalog: [Mention]) -> [Mention] {
        catalog.sorted { $0.name.count > $1.name.count }
    }

    /// Every resolved `@mention` in `text`, with the character range covering
    /// the `@` and the name. Ranges are in UTF-16 units, ready for AppKit.
    static func matches(in text: String, catalog: [Mention]) -> [(range: NSRange, mention: Mention)] {
        guard !catalog.isEmpty else { return [] }
        let ordered = sorted(catalog)
        let ns = text as NSString
        var out: [(NSRange, Mention)] = []
        var i = 0
        while i < ns.length {
            guard ns.character(at: i) == UInt16(UnicodeScalar("@").value), isBoundary(ns, before: i) else {
                i += 1
                continue
            }
            let rest = ns.substring(from: i + 1)
            if let hit = ordered.first(where: {
                rest.lowercased().hasPrefix($0.name.lowercased()) && endsCleanly(rest, after: $0.name.count)
            }) {
                out.append((NSRange(location: i, length: 1 + (hit.name as NSString).length), hit))
                i += 1 + (hit.name as NSString).length
            } else {
                i += 1
            }
        }
        return out
    }

    static func mentions(in text: String, catalog: [Mention]) -> [Mention] {
        var seen = Set<Mention>()
        return matches(in: text, catalog: catalog).compactMap { seen.insert($0.mention).inserted ? $0.mention : nil }
    }

    /// The in-progress `@query` the caret sits in, if any — what the picker
    /// filters on. Nil once the text stops looking like a name being typed.
    static func activeQuery(in text: String, caret: Int) -> (start: Int, query: String)? {
        let ns = text as NSString
        guard caret <= ns.length else { return nil }
        var i = caret - 1
        var scanned = 0
        while i >= 0, scanned <= 40 {
            let ch = Character(UnicodeScalar(ns.character(at: i)) ?? " ")
            if ch == "@" {
                guard isBoundary(ns, before: i) else { return nil }
                return (i, ns.substring(with: NSRange(location: i + 1, length: caret - i - 1)))
            }
            if ch.isNewline { return nil }
            i -= 1
            scanned += 1
        }
        return nil
    }

    /// `@` only starts a mention at the start of a line or after whitespace,
    /// so email addresses in pasted text don't light up.
    private static func isBoundary(_ ns: NSString, before index: Int) -> Bool {
        guard index > 0 else { return true }
        let prev = Character(UnicodeScalar(ns.character(at: index - 1)) ?? " ")
        return prev.isWhitespace || prev == "(" || prev == "["
    }

    /// A name must be followed by a word break — "@Maya" shouldn't match
    /// inside "@Mayapple".
    private static func endsCleanly(_ rest: String, after count: Int) -> Bool {
        let idx = rest.index(rest.startIndex, offsetBy: count, limitedBy: rest.endIndex) ?? rest.endIndex
        guard idx < rest.endIndex else { return true }
        let next = rest[idx]
        return !(next.isLetter || next.isNumber)
    }
}

extension AppState {
    /// Everything `@` can reach, in picker order.
    var mentionCatalog: [Mention] {
        var out: [Mention] = []
        for cls in classroom.classes where !cls.name.isEmpty {
            out.append(Mention(kind: .section, id: cls.id.uuidString, name: cls.name,
                               subtitle: cls.gradeLevel.isEmpty ? "Class" : cls.gradeLevel))
            for s in cls.students where !s.name.isEmpty {
                out.append(Mention(kind: .student, id: s.id.uuidString, name: s.name, subtitle: cls.name))
            }
        }
        for r in allRubrics { out.append(Mention(kind: .rubric, id: r.id, name: r.title, subtitle: r.meta)) }
        for a in allActivities { out.append(Mention(kind: .activity, id: a.id, name: a.title, subtitle: a.meta)) }
        for p in allPogs { out.append(Mention(kind: .pog, id: p.id, name: p.title, subtitle: p.meta)) }
        for q in allQuizzes { out.append(Mention(kind: .quiz, id: q.id, name: q.title, subtitle: q.meta)) }
        return out
    }

    /// Picker results for a partially typed name. An empty query lists a
    /// sample of everything so `@` alone is still useful.
    func mentionSuggestions(for query: String, limit: Int = 8) -> [Mention] {
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        let catalog = mentionCatalog
        guard !q.isEmpty else { return Array(catalog.prefix(limit)) }
        let prefix = catalog.filter { $0.name.lowercased().hasPrefix(q) }
        let contains = catalog.filter { !$0.name.lowercased().hasPrefix(q) && $0.name.lowercased().contains(q) }
        return Array((prefix + contains).prefix(limit))
    }

    /// What the model actually receives for the mentions in a message: the
    /// roster note, the rubric's criteria, the activity's steps — the content
    /// behind the name, never shown in the bubble.
    func mentionContext(for text: String) -> String? {
        let mentions = MentionScanner.mentions(in: text, catalog: mentionCatalog)
        guard !mentions.isEmpty else { return nil }
        let blocks = mentions.compactMap(detail(for:))
        guard !blocks.isEmpty else { return nil }
        return "The teacher referenced these with @ — use them directly:\n\n"
            + blocks.joined(separator: "\n\n")
    }

    private func detail(for mention: Mention) -> String? {
        switch mention.kind {
        case .student:
            guard let (cls, student) = findStudent(id: mention.id) else { return nil }
            var s = "[Student: \(student.name)] in \(cls.name)"
            if !cls.gradeLevel.isEmpty { s += " (\(cls.gradeLevel))" }
            if !student.notes.isEmpty { s += "\nTeacher's notes: \(student.notes)" }
            return s
        case .section:
            guard let cls = classroom.classes.first(where: { $0.id.uuidString == mention.id }) else { return nil }
            var s = "[Class: \(cls.name)]"
            if !cls.gradeLevel.isEmpty { s += " \(cls.gradeLevel)" }
            if !cls.notes.isEmpty { s += "\n\(cls.notes)" }
            let roster = cls.students.filter { !$0.name.isEmpty }
            if !roster.isEmpty {
                s += "\nStudents: " + roster.map { r in
                    r.notes.isEmpty ? r.name : "\(r.name) (\(r.notes))"
                }.joined(separator: "; ")
            }
            return s
        case .rubric:
            guard let r = rubric(id: mention.id) else { return nil }
            var s = "[Rubric: \(r.title)] \(r.sub)"
            for c in r.criteria {
                s += "\n- \(c.name): " + c.cells.enumerated()
                    .map { "\(SampleData.levels4[$0.offset]) — \($0.element)" }
                    .joined(separator: " | ")
            }
            return s
        case .activity:
            guard let a = activity(id: mention.id) else { return nil }
            var s = "[Activity: \(a.title)] \(a.meta)\n\(a.desc)"
            for (i, step) in a.steps.enumerated() { s += "\n\(i + 1). \(step)" }
            return s
        case .pog:
            guard let p = pog(id: mention.id) else { return nil }
            var s = "[Portrait of a Graduate: \(p.title)] \(p.sub)"
            for c in p.comps { s += "\n- \(c.name) (level \(c.level)/5): \(c.desc)" }
            return s
        case .quiz:
            guard let q = quiz(id: mention.id) else { return nil }
            var s = "[Quiz: \(q.title)] \(q.meta)"
            for (i, question) in q.questions.enumerated() {
                s += "\n\(i + 1). \(question.prompt)"
                if !question.choices.isEmpty { s += " [" + question.choices.joined(separator: " / ") + "]" }
            }
            return s
        }
    }

    private func findStudent(id: String) -> (ClassSection, Student)? {
        for cls in classroom.classes {
            if let s = cls.students.first(where: { $0.id.uuidString == id }) { return (cls, s) }
        }
        return nil
    }
}
