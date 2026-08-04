import SwiftUI

/// Drives one placement and reports where it has got to.
///
/// The model runs on a single serial queue shared with chat, so an evaluation
/// and a chat reply cannot overlap — they'd queue behind each other and the
/// app would look frozen. `AppState.isEvaluating` is the interlock; both sides
/// check it.
@MainActor
final class EvaluationRunner: ObservableObject {
    enum Phase: Equatable {
        case idle
        case running(String)
        case done
        case cancelled
        case failed(String)

        var isRunning: Bool { if case .running = self { return true }; return false }
    }

    @Published private(set) var phase: Phase = .idle
    @Published private(set) var result: SkillEvaluation?

    private var task: Task<Void, Never>?

    func run(work: WorkDocument, skill: ComponentSkill, framework: XQFramework,
             workLabel: String, state: AppState) {
        guard !phase.isRunning else { return }
        result = nil
        phase = .running("Starting")
        state.isEvaluating = true

        task = Task { [weak self] in
            guard let self else { return }
            do {
                let placement = try await EvaluationPipeline.evaluate(
                    work: work, skill: skill, backend: state.backend,
                    onStage: { [weak self] stage in
                        Task { @MainActor in
                            guard let self, self.phase.isRunning else { return }
                            self.phase = .running(stage)
                        }
                    })
                try Task.checkCancellation()
                result = Self.record(placement: placement, work: work, skill: skill,
                                     framework: framework, workLabel: workLabel)
                phase = .done
            } catch is CancellationError {
                phase = .cancelled
            } catch {
                phase = .failed(error.localizedDescription)
            }
            state.isEvaluating = false
            task = nil
        }
    }

    func cancel() {
        task?.cancel()
        task = nil
        phase = .cancelled
    }

    /// The teacher moving the placement. The model's own number stays in
    /// `levelOrdinal` — this records a disagreement, it doesn't erase one.
    func applyTeacherLevel(_ ordinal: Int) {
        result?.teacherLevel = ordinal
    }

    /// Snapshot-only: drops a finished record in without running anything.
    func seedForSnapshot(_ evaluation: SkillEvaluation) {
        result = evaluation
        phase = .done
    }

    func reset() {
        cancel()
        result = nil
        phase = .idle
    }

    /// Snapshots the framework wording into the record, so it still reads
    /// correctly after a framework upgrade renames the skill underneath it.
    private static func record(placement: SkillPlacement, work: WorkDocument,
                               skill: ComponentSkill, framework: XQFramework,
                               workLabel: String) -> SkillEvaluation {
        let rung = skill.rung(placement.level)
        return SkillEvaluation(
            id: "eval-\(UUID().uuidString)",
            createdAt: Date(),
            workLabel: workLabel.isEmpty ? (work.sourceName ?? "Untitled work") : workLabel,
            workSnippet: String(work.text.prefix(600)),
            workCharacterCount: work.text.count,
            sourceName: work.sourceName,
            skillId: skill.id,
            competencyId: skill.competencyId,
            skillName: skill.name,
            competencyName: skill.competencyName,
            frameworkVersion: framework.version,
            levelOrdinal: placement.level,
            levelLabel: framework.levelLabel(placement.level),
            levelDescriptor: rung?.descriptor ?? "",
            evidence: placement.evidenceSentences.compactMap { work.sentence($0) },
            nextStep: placement.nextStep,
            hasMixedEvidence: placement.hasMixedEvidence,
            isOffTopic: !placement.isRelevant,
            teacherLevel: nil)
    }
}
