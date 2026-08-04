import Foundation

/// Reads the bundled XQ competency CSVs into an `XQFramework`.
///
/// Everything here is deliberately forgiving in one direction only: a row that
/// can't be joined to its parent is *kept* and reported, never dropped. A skill
/// carries its own name, detail and progression, which is all an evaluation
/// needs — silently shrinking 115 to 114 would be much worse than an orphan.
enum FrameworkImport {
    struct Diagnostics {
        var counts: [String: Int] = [:]
        var malformedRows = 0
        var duplicateIds: [String] = []
        var orphanSkillIds: [String] = []
        var orphanCompetencyIds: [String] = []
        var skillsMissingProgression: [String] = []

        var isClean: Bool {
            malformedRows == 0 && duplicateIds.isEmpty && orphanSkillIds.isEmpty
                && orphanCompetencyIds.isEmpty && skillsMissingProgression.isEmpty
        }

        var summary: String {
            let counted = ["learner_outcomes", "domains", "competencies", "component_skills"]
                .map { "\($0): \(counts[$0] ?? 0)" }
                .joined(separator: ", ")
            var lines = [counted]
            if malformedRows > 0 { lines.append("malformed rows: \(malformedRows)") }
            if !duplicateIds.isEmpty { lines.append("duplicate ids: \(duplicateIds.joined(separator: ", "))") }
            if !orphanSkillIds.isEmpty { lines.append("orphan skills: \(orphanSkillIds.joined(separator: ", "))") }
            if !orphanCompetencyIds.isEmpty { lines.append("orphan competencies: \(orphanCompetencyIds.joined(separator: ", "))") }
            if !skillsMissingProgression.isEmpty { lines.append("skills without a progression: \(skillsMissingProgression.joined(separator: ", "))") }
            return lines.joined(separator: "\n")
        }
    }

    enum Failure: LocalizedError {
        case directoryMissing
        case fileMissing(String)
        case badSchema(String)

        var errorDescription: String? {
            switch self {
            case .directoryMissing:
                return "The XQ competency framework is missing from the app bundle."
            case .fileMissing(let name):
                return "The competency framework file \(name) is missing."
            case .badSchema(let name):
                return "The competency framework file \(name) doesn't have the columns this version expects."
            }
        }
    }

    /// Bundle first, then a test override, then the source checkout — the same
    /// order (and the same reasoning) as `LlamaBackend.locateModelFile()`.
    static func resourceDirectory() -> URL? {
        let fm = FileManager.default
        if let bundled = Bundle.main.resourceURL?.appendingPathComponent("XQFramework"),
           fm.fileExists(atPath: bundled.path) {
            return bundled
        }
        if let override = ProcessInfo.processInfo.environment["TW_FRAMEWORK_DIR"] {
            return URL(fileURLWithPath: override, isDirectory: true)
        }
        let dev = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()   // TeacherWorkspace/
            .deletingLastPathComponent()   // Sources/
            .deletingLastPathComponent()   // package root
            .appendingPathComponent("Resources/XQFramework", isDirectory: true)
        return fm.fileExists(atPath: dev.path) ? dev : nil
    }

    static func load() throws -> (XQFramework, Diagnostics) {
        guard let dir = resourceDirectory() else { throw Failure.directoryMissing }
        return try load(from: dir)
    }

    static func load(from dir: URL) throws -> (XQFramework, Diagnostics) {
        var diagnostics = Diagnostics()

        func table(_ name: String, requiring: [String]) throws -> CSVTable {
            let url = dir.appendingPathComponent("\(name).csv")
            guard let text = try? String(contentsOf: url, encoding: .utf8) else {
                throw Failure.fileMissing("\(name).csv")
            }
            guard let parsed = CSVTable(text: text, requiring: requiring) else {
                throw Failure.badSchema("\(name).csv")
            }
            diagnostics.counts[name] = parsed.rows.count
            diagnostics.malformedRows += parsed.malformedRowCount
            return parsed
        }

        let outcomesTable = try table("learner_outcomes", requiring: ["id", "name"])
        let domainsTable = try table("domains", requiring: ["id", "learner_outcome_id", "name"])
        let competenciesTable = try table("competencies", requiring: ["id", "domain_id", "name"])
        let skillsTable = try table("component_skills", requiring: ["id", "competency_id", "name"])

        var seen = Set<String>()
        func claim(_ id: String) -> Bool {
            guard !id.isEmpty else { return false }
            if seen.contains(id) {
                diagnostics.duplicateIds.append(id)
                return false
            }
            seen.insert(id)
            return true
        }

        let outcomes: [LearnerOutcome] = outcomesTable.rows.compactMap { row in
            let id = outcomesTable.value(row, "id")
            guard claim(id) else { return nil }
            return LearnerOutcome(id: id,
                                  name: outcomesTable.value(row, "name"),
                                  detail: outcomesTable.value(row, "description"))
        }

        let domains: [Domain] = domainsTable.rows.compactMap { row in
            let id = domainsTable.value(row, "id")
            guard claim(id) else { return nil }
            return Domain(id: id,
                          learnerOutcomeId: domainsTable.value(row, "learner_outcome_id"),
                          name: domainsTable.value(row, "name"))
        }

        let competencies: [Competency] = competenciesTable.rows.compactMap { row in
            let id = competenciesTable.value(row, "id")
            guard claim(id) else { return nil }
            return Competency(id: id,
                              learnerOutcomeId: competenciesTable.value(row, "learner_outcome_id"),
                              domainId: competenciesTable.value(row, "domain_id"),
                              domainName: competenciesTable.value(row, "domain_name"),
                              name: competenciesTable.value(row, "name"),
                              tagline: competenciesTable.value(row, "tagline"),
                              detail: competenciesTable.value(row, "description"))
        }

        let progressionColumns = progressionColumns(in: skillsTable.headers)
        let skills: [ComponentSkill] = skillsTable.rows.compactMap { row in
            let id = skillsTable.value(row, "id")
            guard claim(id) else { return nil }
            let rungs: [ProgressionRung] = progressionColumns.compactMap { column in
                let text = skillsTable.value(row, column.header)
                guard !text.isEmpty else { return nil }
                return ProgressionRung(ordinal: column.ordinal, label: column.label, descriptor: text)
            }
            if rungs.count < 2 { diagnostics.skillsMissingProgression.append(id) }
            return ComponentSkill(id: id,
                                  competencyId: skillsTable.value(row, "competency_id"),
                                  competencyName: skillsTable.value(row, "competency_name"),
                                  learnerOutcomeId: skillsTable.value(row, "learner_outcome_id"),
                                  name: skillsTable.value(row, "name"),
                                  detail: skillsTable.value(row, "description"),
                                  example: skillsTable.value(row, "example"),
                                  progression: rungs)
        }

        let competencyIds = Set(competencies.map(\.id))
        let domainIds = Set(domains.map(\.id))
        diagnostics.orphanSkillIds = skills.filter { !competencyIds.contains($0.competencyId) }.map(\.id)
        diagnostics.orphanCompetencyIds = competencies.filter { !domainIds.contains($0.domainId) }.map(\.id)

        var framework = XQFramework(
            version: readVersion(in: dir),
            learnerOutcomes: outcomes,
            domains: domains,
            competencies: competencies,
            componentSkills: skills,
            levelLabels: progressionColumns.map(\.label))
        framework.rebuildIndex()
        return (framework, diagnostics)
    }

    /// Level names come from the header row: `progression_level_2_developing`
    /// yields ordinal 2, label "Developing". Reading them rather than hardcoding
    /// four is what lets an upstream change of scale pass through untouched.
    private static func progressionColumns(in headers: [String])
        -> [(header: String, ordinal: Int, label: String)] {
        headers.compactMap { header in
            guard header.hasPrefix("progression_level_") else { return nil }
            let rest = header.dropFirst("progression_level_".count)
            let parts = rest.split(separator: "_", maxSplits: 1)
            guard parts.count == 2, let ordinal = Int(parts[0]) else { return nil }
            let label = parts[1].replacingOccurrences(of: "_", with: " ").capitalized
            return (header, ordinal, label)
        }
        .sorted { $0.ordinal < $1.ordinal }
    }

    /// VERSION is a small key/value file; the line we want reads "Version: 1.1.0".
    private static func readVersion(in dir: URL) -> String {
        guard let raw = try? String(contentsOf: dir.appendingPathComponent("VERSION"), encoding: .utf8)
        else { return "unknown" }
        for line in raw.split(separator: "\n") where line.lowercased().hasPrefix("version:") {
            return line.dropFirst("version:".count).trimmingCharacters(in: .whitespaces)
        }
        return "unknown"
    }
}
