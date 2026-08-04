import Foundation

// The XQ competency framework: 5 learner outcomes → 13 domains → 37
// competencies → 115 component skills, each with a 4-level progression.
//
// Bundled rather than downloaded. It's 180KB, it changes about yearly, and a
// teacher behind a school proxy that blocks github.com would otherwise get a
// screen that never works. Updates ride an app release.
//
// Source: github.com/xq-labs/xq-competencies, © XQ Institute, CC BY 4.0.
// Attribution is a licence condition — see `attribution`, which every screen
// and export that shows this data is required to display.

/// One rung of a progression. `ordinal` is 1-based and comes from the CSV
/// column name, never from a position in an array.
struct ProgressionRung: Codable, Hashable {
    var ordinal: Int
    var label: String
    var descriptor: String
}

struct LearnerOutcome: Codable, Hashable, Identifiable {
    var id: String              // "FK"
    var name: String
    var detail: String
}

struct Domain: Codable, Hashable, Identifiable {
    var id: String              // "FK.AC"
    var learnerOutcomeId: String
    var name: String
}

struct Competency: Codable, Hashable, Identifiable {
    var id: String              // "FK.AC.1"
    var learnerOutcomeId: String
    var domainId: String
    var domainName: String
    var name: String
    var tagline: String
    var detail: String
}

struct ComponentSkill: Codable, Hashable, Identifiable {
    var id: String              // "FK.AC.1.a"
    var competencyId: String
    var competencyName: String
    var learnerOutcomeId: String
    var name: String
    var detail: String
    var example: String
    var progression: [ProgressionRung]

    func rung(_ ordinal: Int) -> ProgressionRung? {
        progression.first { $0.ordinal == ordinal }
    }
}

struct XQFramework {
    var version: String
    var learnerOutcomes: [LearnerOutcome]
    var domains: [Domain]
    var competencies: [Competency]
    var componentSkills: [ComponentSkill]

    /// Level names as they were read from the CSV headers, in ordinal order.
    /// Data, not a constant: an upstream release with a different number of
    /// rungs becomes a non-event instead of a crash. Deliberately *not* merged
    /// with `SampleData.levels4`, which names the app's own rubric levels —
    /// unifying them would silently relabel every rubric a teacher has.
    var levelLabels: [String]

    /// Never subscript `levelLabels` directly; an out-of-range rung is a
    /// display problem, not a reason to trap.
    func levelLabel(_ ordinal: Int) -> String {
        guard ordinal >= 1, ordinal <= levelLabels.count else { return "Level \(ordinal)" }
        return levelLabels[ordinal - 1]
    }

    func skill(id: String) -> ComponentSkill? { index.skillsById[id] }
    func competency(id: String) -> Competency? { index.competenciesById[id] }

    /// Required wherever this data is shown. CC BY 4.0 is a condition, not a
    /// courtesy.
    var attribution: String { "XQ Competencies v\(version) · © XQ Institute · CC BY 4.0" }

    // Derived lookups. Rebuilt with the framework, never persisted.
    private(set) var index = FrameworkIndex()

    struct FrameworkIndex {
        var skillsById: [String: ComponentSkill] = [:]
        var competenciesById: [String: Competency] = [:]
        var domainsById: [String: Domain] = [:]
        var skillIdsByCompetency: [String: [String]] = [:]
        var competencyIdsByOutcome: [String: [String]] = [:]
        /// Lowercased haystack per skill, for the picker's search and the
        /// lexical suggestions. Built once so typing stays instant.
        var searchText: [String: String] = [:]
    }

    mutating func rebuildIndex() {
        var i = FrameworkIndex()
        for s in componentSkills {
            i.skillsById[s.id] = s
            i.skillIdsByCompetency[s.competencyId, default: []].append(s.id)
            i.searchText[s.id] = [s.name, s.detail, s.example, s.competencyName]
                .joined(separator: " ").lowercased()
        }
        for c in competencies {
            i.competenciesById[c.id] = c
            i.competencyIdsByOutcome[c.learnerOutcomeId, default: []].append(c.id)
        }
        for d in domains { i.domainsById[d.id] = d }
        index = i
    }
}
