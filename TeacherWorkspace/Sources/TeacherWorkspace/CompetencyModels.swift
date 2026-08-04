import Foundation

// MARK: - Screen 2: Learner profile

struct CompetencyScore: Identifiable {
    var id: String { name }
    var name: String
    var score: Int // 0...100
}

struct ConfidencePoint {
    var value: Int // 0...100
    /// Set only on the point worth calling out (e.g. a dip).
    var note: String?
}

struct PeerTie: Identifiable {
    var id: String { peerName }
    var peerName: String
    var initials: String
    var strength: Double // 0...1, drawn as edge thickness
    var isStrong: Bool { strength >= 0.5 }
}

struct EngagementWeek: Identifiable {
    var id: Int { week }
    var week: Int
    var value: Int // 0...100
}

struct EvidenceNote: Identifiable {
    var id: Int
    var lead: String
    var body: String
}

enum LessonSuggestionKind: String {
    case grouping = "Grouping"
    case entryPoint = "Entry point"
    case stretch = "Stretch"
}

struct LessonSuggestion: Identifiable {
    var id: String { kind.rawValue }
    var kind: LessonSuggestionKind
    var text: String
}

struct LearnerCompetencyProfile: Identifiable {
    var id: String { studentName }
    var studentName: String
    var initials: String
    var gradeLabel: String
    var tags: [String]
    /// Exactly 3 — rendered as concentric donut rings, outer to inner.
    var scores: [CompetencyScore]
    var confidenceTrend: [ConfidencePoint]
    var confidenceCaption: String
    /// Exactly 6 peer nodes around the student in the collaboration network.
    var peerTies: [PeerTie]
    /// Exactly 12 weeks of engagement data.
    var engagement: [EngagementWeek]
    var engagementCaption: String
    /// Exactly 3 observations.
    var evidenceNotes: [EvidenceNote]
    /// Exactly 3 — one per LessonSuggestionKind.
    var lessonSuggestions: [LessonSuggestion]
}

// MARK: - Screen 3: Community opportunity graph

enum PartnerCategory: String, CaseIterable, Hashable {
    case civic = "Civic"
    case culturalEd = "Cultural / ed"
    case industry = "Industry"
    case individuals = "Individuals"
}

struct PartnerNode: Identifiable {
    var id: String { name }
    var name: String
    var category: PartnerCategory
    var strength: Double // 0...1, drawn as edge thickness to the center node
}

struct PartnerOrg: Identifiable {
    var id: String { name }
    var name: String
    var category: PartnerCategory
    var fitScore: Int
    var blurb: String
    var tags: [String]
}

struct CommunityStat: Identifiable {
    var id: String { label }
    var label: String
    var value: String
}

struct CommunityGraphData {
    var unitName: String
    var orgCountLabel: String
    var capacityLabel: String
    /// Exactly 7 — the satellites around the center unit node.
    var nodes: [PartnerNode]
    /// Exactly 3 — index 0 is emphasized as the top recommendation.
    var recommended: [PartnerOrg]
    /// Exactly 4 stat tiles.
    var stats: [CommunityStat]
}

// MARK: - Screen 4: Project / mentor matcher

enum MatchTagKind {
    case gap, strength, interest
}

struct MatchTag: Identifiable {
    var id: String { label }
    var label: String
    var kind: MatchTagKind
}

struct ScoreBreakdownItem: Identifiable {
    var id: String { label }
    var label: String
    var weight: Double // e.g. 0.5
    var rawScore: Int // 0...100
}

struct MatchDetail {
    var commitment: String
    var format: String
    var vetting: String
    var bonus: String
}

struct MatchCandidate: Identifiable {
    var id: String { orgName }
    var orgName: String
    var contactName: String
    var fitScore: Int
    var blurb: String
    /// Populated only on the top (expanded) match.
    var breakdown: [ScoreBreakdownItem]?
    var detail: MatchDetail?
    var draftIntroNote: String?
    /// Populated only on the lowest-ranked match.
    var lowRankReason: String?
}

struct MatcherProfile: Identifiable {
    var id: String { studentName }
    var studentName: String
    var initials: String
    var matchingTags: [MatchTag]
    /// Exactly 3, ranked best-fit first.
    var matches: [MatchCandidate]
}
