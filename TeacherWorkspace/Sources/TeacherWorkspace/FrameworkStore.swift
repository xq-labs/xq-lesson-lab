import SwiftUI

/// Loads the bundled competency framework once and hands it to whoever needs
/// it. Shaped like `ModelDownloader` because that's the async-resource idiom
/// already in the app — a phase enum and an ObservableObject.
///
/// Parsing 115 skills takes a few milliseconds, but it happens off the main
/// thread anyway: the Skill Check screen shouldn't cost the first frame.
@MainActor
final class FrameworkStore: ObservableObject {
    static let shared = FrameworkStore()

    enum Phase: Equatable {
        case idle, loading, ready
        case failed(String)
    }

    @Published private(set) var phase: Phase = .idle
    private(set) var framework: XQFramework?

    private init() {}

    /// Synchronous adoption for headless probe paths (TW_PROBE), where the
    /// async load's main-actor Task never gets to run because the probe
    /// blocks the main thread on a semaphore. The app itself always goes
    /// through `loadIfNeeded`.
    func adopt(_ loaded: XQFramework) {
        guard framework == nil else { return }
        framework = loaded
        phase = .ready
    }

    func loadIfNeeded() {
        guard phase == .idle else { return }
        phase = .loading
        Task {
            do {
                let (loaded, diagnostics) = try await Task.detached(priority: .userInitiated) {
                    try FrameworkImport.load()
                }.value
                framework = loaded
                phase = .ready
                if !diagnostics.isClean {
                    // Not fatal — orphans are kept and everything still places.
                    // TW_FRAMEWORK_CHECK is where this gets caught before ship.
                    print("XQ framework loaded with problems:\n\(diagnostics.summary)")
                }
            } catch {
                phase = .failed(error.localizedDescription)
            }
        }
    }

    /// Skills matching `query`, ranked by where the match lands. Pure string
    /// work — no model involved in choosing what a teacher is offered.
    func search(_ query: String, limit: Int = 60) -> [ComponentSkill] {
        guard let framework else { return [] }
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !needle.isEmpty else { return framework.componentSkills }
        return framework.componentSkills
            .compactMap { skill -> (ComponentSkill, Int)? in
                if skill.name.lowercased().contains(needle) { return (skill, 0) }
                if skill.competencyName.lowercased().contains(needle) { return (skill, 1) }
                if framework.index.searchText[skill.id]?.contains(needle) == true { return (skill, 2) }
                return nil
            }
            .sorted { $0.1 < $1.1 }
            .prefix(limit)
            .map(\.0)
    }

    /// Skills whose wording overlaps the work most. Deliberately lexical: a 2B
    /// model asked to name a skill out of 115 invents ids that look real, and
    /// the roadmap already settled that curated data beats model recall here.
    /// These are suggestions a teacher confirms, never an automatic choice.
    func suggestions(for text: String, limit: Int = 5) -> [ComponentSkill] {
        guard let framework else { return [] }
        let stopwords: Set<String> = [
            "the", "and", "that", "this", "with", "from", "they", "them", "their",
            "have", "has", "had", "was", "were", "for", "are", "but", "not", "you",
            "can", "will", "would", "could", "about", "into", "than", "then", "there",
            "what", "when", "which", "who", "how", "his", "her", "its", "our", "your",
            "student", "students", "work",
        ]
        let words = Set(
            text.lowercased()
                .components(separatedBy: CharacterSet.alphanumerics.inverted)
                .filter { $0.count > 3 && !stopwords.contains($0) })
        guard !words.isEmpty else { return [] }

        return framework.componentSkills
            .map { skill -> (ComponentSkill, Int) in
                let haystack = framework.index.searchText[skill.id] ?? ""
                let hits = words.filter { haystack.contains($0) }.count
                return (skill, hits)
            }
            .filter { $0.1 >= 2 }
            .sorted { $0.1 > $1.1 }
            .prefix(limit)
            .map(\.0)
    }
}
