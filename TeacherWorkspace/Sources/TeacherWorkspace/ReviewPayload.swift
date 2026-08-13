import Foundation

/// Exactly what a frontier model is asked to do, per artifact type.
///
/// One well-specified critique beats a free-form "review this": a reviewer
/// told to look at pacing and assessment gives a teacher something to act on,
/// where an open prompt gives back a summary of the document they just wrote.
enum ReviewPrompts {

    static let preamble = """
        You are giving a second opinion to a working teacher on a document they \
        wrote. Names have been removed before this reached you — students appear \
        as "Student A", "Student B" and so on. Do not ask for the names, and do \
        not invent any.

        Be specific and concrete. Point at particular lines, steps or criteria. \
        A vague compliment is worse than no compliment; a teacher can't act on it.
        """

    static func focus(for type: ArtifactType) -> String {
        switch type {
        case .activity:
            return """
                This is a lesson plan or classroom activity. Look hardest at: \
                whether the timing is realistic for the number of steps; whether \
                there is a way to tell who understood before the period ends; \
                whether a student who finishes early and a student who is stuck \
                both have somewhere to go; and whether the opening actually hooks.
                """
        case .rubric:
            return """
                This is a scoring rubric. Look hardest at: whether adjacent levels \
                describe genuinely different work rather than "more" or "better" of \
                the same thing; whether a criterion measures something a student can \
                control; whether two teachers scoring the same work would land in the \
                same place; and whether anything important is being assessed twice.
                """
        case .quiz:
            return """
                This is a quiz or exit ticket. Look hardest at: whether each question \
                tests understanding rather than recall of wording; whether the wrong \
                answers are plausible enough to be diagnostic; whether any question \
                gives away another; and whether the whole thing fits the time a teacher \
                would actually have.
                """
        case .pog:
            return """
                This is a Portrait of a Graduate — a competency profile of one student. \
                Look hardest at: whether each judgment is tied to something observable \
                rather than to a personality trait; whether the language would be fair \
                and useful if the student and their family read it; and whether the \
                levels are consistent with the descriptions beside them.
                """
        case .email:
            return """
                This is a draft message to families. Look hardest at: whether the ask is \
                clear in the first two lines; whether the tone would land well with a \
                family already worried; whether it assumes school knowledge a family may \
                not have; and whether anything reads as blame.
                """
        }
    }

    /// The response shape. Kept small on purpose — a review a teacher won't
    /// finish reading is a review that changes nothing.
    static let format = """
        Reply with three strengths, three suggestions, and up to two questions \
        worth thinking about. Each suggestion needs a short title and two or three \
        sentences saying what to change and why. Where a suggestion is about a \
        specific numbered step or criterion, say which number.
        """

    static func instructions(for type: ArtifactType) -> String {
        [preamble, focus(for: type), format].joined(separator: "\n\n")
    }
}

/// The only thing the transport will accept.
///
/// `ChatBackend` takes `[ChatTurn]` — an array of unconstrained `String` — so
/// no conformer can promise anything about what it carries. This type can,
/// because it has exactly one initializer and that initializer runs the gate.
/// A payload that would leak a known name cannot be constructed, which is a
/// stronger guarantee than a rule that says it must not be.
struct ReviewPayload {
    let subjectRef: ArtifactRef
    let subjectTitle: String
    let instructions: String
    /// The redacted artifact markdown.
    let body: String
    let profile: ClassProfile?
    let question: String?

    /// For the consent sheet only. Never serialized outward — a list of
    /// "Maya Rodriguez → Student A" pairs is the one document that would undo
    /// the whole exercise.
    let redactions: [Redaction]
    /// Matches left in place because they are also ordinary words.
    let flagged: [Redaction]
    /// Names `NLTagger` spotted that the roster doesn't know. Advisory.
    let advisories: [RedactionGate.Finding]
    /// Pins the pseudonym mapping so a saved review can be re-personalised for
    /// display later. UUIDs, not names.
    let studentIdOrder: [String]

    /// Builds a payload from a rendered artifact. Throws `RedactionGate.Blocked`
    /// if anything the app knows to be identifying survives.
    init(ref: ArtifactRef,
         title: String,
         markdown: String,
         profile: ClassProfile? = nil,
         question: String? = nil,
         lexicon: PIILexicon) throws {
        let cleanedTitle = Deidentifier.process(title, lexicon: lexicon)
        let cleanedBody = Deidentifier.process(markdown, lexicon: lexicon)
        let cleanedQuestion = question.map { Deidentifier.process($0, lexicon: lexicon) }

        subjectRef = ref
        subjectTitle = cleanedTitle.text
        instructions = ReviewPrompts.instructions(for: ref.type)
        body = cleanedBody.text
        self.profile = profile
        self.question = cleanedQuestion?.text.trimmingCharacters(in: .whitespacesAndNewlines)
            .nilIfEmpty
        // Merged across title, body and question so the sheet shows one row
        // per thing removed, not one per place it appeared.
        redactions = Deidentifier.merge(cleanedTitle.redactions + cleanedBody.redactions
            + (cleanedQuestion?.redactions ?? []))
        flagged = Deidentifier.merge(cleanedTitle.flagged + cleanedBody.flagged
            + (cleanedQuestion?.flagged ?? []))
        studentIdOrder = lexicon.studentIdOrder

        let findings = RedactionGate.verify(Self.compose(
            instructions: instructions, profile: profile,
            question: self.question, body: body), lexicon: lexicon)
        advisories = findings.filter { !$0.isBlocking }

        let blocking = findings.filter(\.isBlocking)
        guard blocking.isEmpty else { throw RedactionGate.Blocked(findings: blocking) }
    }

    /// Rebuilds after the teacher edits the payload in the consent sheet.
    /// Runs the gate again — the edit is exactly where a name comes back.
    func edited(body newBody: String, question newQuestion: String?,
                lexicon: PIILexicon) throws -> ReviewPayload {
        let trimmedQuestion = newQuestion?
            .trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
        let composed = Self.compose(instructions: instructions, profile: profile,
                                    question: trimmedQuestion, body: newBody)
        let findings = RedactionGate.verify(composed, lexicon: lexicon)
        let blocking = findings.filter(\.isBlocking)
        guard blocking.isEmpty else { throw RedactionGate.Blocked(findings: blocking) }

        return ReviewPayload(
            subjectRef: subjectRef, subjectTitle: subjectTitle, instructions: instructions,
            body: newBody, profile: profile, question: trimmedQuestion,
            redactions: redactions, flagged: flagged,
            advisories: findings.filter { !$0.isBlocking }, studentIdOrder: studentIdOrder)
    }

    /// Private memberwise init for `edited`. The public path is the throwing
    /// one above; this one is only reachable from a payload that already passed.
    private init(subjectRef: ArtifactRef, subjectTitle: String, instructions: String,
                 body: String, profile: ClassProfile?, question: String?,
                 redactions: [Redaction], flagged: [Redaction],
                 advisories: [RedactionGate.Finding], studentIdOrder: [String]) {
        self.subjectRef = subjectRef
        self.subjectTitle = subjectTitle
        self.instructions = instructions
        self.body = body
        self.profile = profile
        self.question = question
        self.redactions = redactions
        self.flagged = flagged
        self.advisories = advisories
        self.studentIdOrder = studentIdOrder
    }

    /// Exactly what the consent sheet shows and the request body carries. The
    /// sheet must never render a prettified version of this — the whole point
    /// is that the teacher reads the real thing.
    var outgoingText: String {
        Self.compose(instructions: instructions, profile: profile, question: question, body: body)
    }

    var byteCount: Int { outgoingText.utf8.count }

    var wordCount: Int {
        outgoingText.split(whereSeparator: { $0.isWhitespace }).count
    }

    private static func compose(instructions: String, profile: ClassProfile?,
                                question: String?, body: String) -> String {
        var out = instructions
        if let profile {
            out += "\n\nABOUT THE CLASS: \(profile.summaryLine)"
        }
        if let question, !question.isEmpty {
            out += "\n\nTHE TEACHER ALSO ASKS: \(question)"
        }
        out += "\n\n---\n\n" + body
        return out
    }
}

extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}
