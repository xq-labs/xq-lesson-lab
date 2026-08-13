import Foundation

/// A saved second opinion.
///
/// Deliberately **not** an `ArtifactType`. That enum is `Codable` and lives
/// inside `ArtifactRef` → `Message.artifact` → `extraMessages`, which is a
/// non-optional field on `PersistedState` — a store written by a build that
/// knew a sixth case and read by one that didn't would fail to decode and
/// take every chat, artifact, and the classroom with it. A critique is not
/// an artifact anyway: the teacher wrote the document, a model commented on it.
struct FrontierReview: Identifiable, Codable, Equatable {
    var id: String
    var createdAt: Date

    var subjectRef: ArtifactRef
    /// Snapshotted, so the review still reads correctly after the artifact is
    /// renamed — the same reason `SkillEvaluation` snapshots framework text.
    var subjectTitle: String

    var providerId: String
    var modelId: String
    var modelDisplayName: String

    var strengths: [String]
    var suggestions: [ReviewSuggestion]
    var questions: [String]

    /// The receipt: exactly the bytes that left this Mac, verbatim. The single
    /// most trust-generating field in the feature — it turns "we promised"
    /// into "here it is, forever."
    var payloadSent: String
    var requestBytes: Int
    /// Links back to the audit log line for this send.
    var auditEntryId: String

    /// Pins the pseudonym mapping so "Student A" can be rendered back as a
    /// real first name on screen, months later, without ever writing a
    /// name-beside-pseudonym table to disk. UUID strings, not names.
    var studentIdOrder: [String]

    var title: String { "Review — \(subjectTitle)" }

    var summaryLine: String {
        var parts: [String] = []
        if !strengths.isEmpty { parts.append("\(strengths.count) strength\(strengths.count == 1 ? "" : "s")") }
        if !suggestions.isEmpty { parts.append("\(suggestions.count) suggestion\(suggestions.count == 1 ? "" : "s")") }
        if !questions.isEmpty { parts.append("\(questions.count) question\(questions.count == 1 ? "" : "s")") }
        return parts.joined(separator: ", ")
    }

    static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .none
        return f
    }()

    var dateLine: String { Self.dateFormatter.string(from: createdAt) }

    /// The line that appears on screen, in the markdown export, and on the
    /// printed PDF. Says where it ran, what it saw, and whose call it is.
    var provenanceLine: String {
        "Reviewed off-device by \(modelDisplayName) on \(dateLine). "
            + "It saw the text below and nothing else — \(requestBytes) de-identified "
            + "bytes were sent. It's a second opinion; you decide."
    }

    /// Renders stored pseudonyms back to real names for display only. The
    /// saved text stays de-identified; this is a view over it.
    ///
    /// A student who has since left the roster keeps their pseudonym — visible
    /// and honest, rather than silently re-pointed at whoever now sorts into
    /// that slot.
    func personalized(_ text: String, classroom: Classroom) -> String {
        let students = classroom.classes.flatMap(\.students).filter { !$0.name.isEmpty }
        let byId = Dictionary(uniqueKeysWithValues: students.map { ($0.id.uuidString, $0) })
        let pseudonyms = PIILexicon.pseudonyms(forStudentIds: studentIdOrder)

        var out = text
        // Longest pseudonym first, so "Student AA" isn't clipped by "Student A".
        for (id, pseudonym) in pseudonyms.sorted(by: { $0.value.count > $1.value.count }) {
            guard let student = byId[id] else { continue }
            let firstName = student.name.split(separator: " ").first.map(String.init) ?? student.name
            out = out.replacingOccurrences(of: pseudonym, with: firstName)
        }
        return out
    }
}
