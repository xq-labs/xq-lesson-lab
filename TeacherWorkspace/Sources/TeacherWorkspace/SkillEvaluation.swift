import Foundation

/// A saved placement of one piece of work against one component skill.
///
/// Deliberately not linked to a student. The teacher labels the assignment,
/// not the child — which keeps a roster name out of the file that holds the
/// work itself.
///
/// The framework text is *snapshotted* rather than looked up on display, so a
/// record still reads correctly after the framework is upgraded and a skill is
/// renamed or re-worded.
struct SkillEvaluation: Identifiable, Codable, Equatable {
    var id: String
    var createdAt: Date

    /// The teacher's own label for the assignment.
    var workLabel: String
    /// Opening of the work, for recognizing the record later. The full text is
    /// deliberately not kept: store.json is rewritten whole on a debounce, and
    /// an archive of student essays is a liability this feature doesn't need.
    var workSnippet: String
    var workCharacterCount: Int
    /// Filename only when it came from a file — never a path, which would
    /// carry the teacher's home directory into the store.
    var sourceName: String?

    var skillId: String
    var competencyId: String
    var skillName: String
    var competencyName: String
    var frameworkVersion: String

    var levelOrdinal: Int
    var levelLabel: String
    var levelDescriptor: String
    /// Verbatim sentences from the work that the ladder pointed at.
    var evidence: [String]
    var nextStep: String?

    /// The ladder came back non-monotonic — a YES above a NO. Kept because a
    /// marginal placement should look marginal.
    var hasMixedEvidence: Bool
    /// The relevance stage doubted this skill applied at all.
    var isOffTopic: Bool
    /// Set when the teacher overrides the placement; the model's number is
    /// never overwritten.
    var teacherLevel: Int?

    /// What the record shows as its level — the teacher's call wins.
    var effectiveLevel: Int { teacherLevel ?? levelOrdinal }

    var title: String { workLabel }
    var sub: String { "\(competencyName) · \(skillName)" }
    var meta: String { "\(levelLabel) · XQ \(frameworkVersion)" }

    /// True when nothing questioned the result — used to decide how loudly the
    /// UI hedges.
    var isConfident: Bool { !hasMixedEvidence && !isOffTopic }
}
