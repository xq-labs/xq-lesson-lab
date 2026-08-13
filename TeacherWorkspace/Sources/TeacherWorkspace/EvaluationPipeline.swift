import Foundation

/// One rung's verdict. `nil` for `meets` means the model's answer couldn't be
/// read — which is different from "no", and is kept different all the way to
/// the screen.
struct RungVerdict {
    var ordinal: Int
    var meets: Bool?
    var evidenceSentence: Int?
}

/// What the pipeline concluded about one component skill.
struct SkillPlacement {
    var skillId: String
    var verdicts: [RungVerdict]
    /// The highest rung whose answer was YES *and* whose cited sentence held up
    /// on its own. Decided in `evaluate` because corroboration costs a call.
    var corroboratedRung: Int?
    var nextStep: String?

    /// Level 1 is the floor: everything below a corroborated rung is implied,
    /// and nothing corroborated means nothing was shown.
    var level: Int { corroboratedRung ?? 1 }

    /// No rung registered at all — not one YES anywhere on the ladder. That's
    /// the shape of a skill the work simply isn't about, and it's the caveat
    /// the old relevance question was meant to provide, earned from the rungs
    /// instead of asked for directly.
    ///
    /// Deliberately *not* "nothing corroborated": a beginner writing thinly
    /// about the right skill answers YES on the low rungs with slight evidence
    /// and lands at the floor. Telling that teacher "this may not be about this
    /// skill" would be wrong — they picked correctly, and Emerging is the
    /// answer.
    var isOffTopic: Bool { verdicts.allSatisfy { $0.meets != true } }

    /// A YES above a NO. The ladder came back incoherent, which is real
    /// information about how marginal the placement is — surfaced, not hidden.
    ///
    /// Note this is now common rather than alarming: XQ rungs aren't strictly
    /// cumulative, so an analytical piece can clear rung 4 while skipping
    /// rung 3's "describe how it makes me feel".
    var hasMixedEvidence: Bool {
        let ordered = verdicts.sorted { $0.ordinal < $1.ordinal }
        guard let firstNo = ordered.firstIndex(where: { $0.meets != true }) else { return false }
        return ordered[firstNo...].contains { $0.meets == true }
    }

    /// Sentence numbers backing the level actually assigned. Only rungs at or
    /// below the corroborated one, so a discarded high YES doesn't smuggle its
    /// sentence onto the card as though it counted.
    var evidenceSentences: [Int] {
        verdicts
            .filter { $0.meets == true && $0.ordinal <= level }
            .compactMap(\.evidenceSentence)
            .filter { $0 > 0 }
    }
}

/// The staged evaluation. Each call is small enough for a 2B model to do one
/// thing; the reconciliation happens here in Swift, where it's inspectable.
///
/// Everything is sequential on purpose — `LlamaBackend` runs one serial queue,
/// so issuing these concurrently would buy no parallelism and only interleave
/// with chat.
enum EvaluationPipeline {
    /// Placing one skill: one call per rung above the floor, then up to one
    /// corroboration call per rung that said YES, then 1 next-step call.
    static func evaluate(work: WorkDocument,
                         skill: ComponentSkill,
                         backend: ChatBackend,
                         onStage: ((String) -> Void)? = nil) async throws -> SkillPlacement {
        var verdicts: [RungVerdict] = []
        for rung in skill.progression.sorted(by: { $0.ordinal < $1.ordinal }) where rung.ordinal > 1 {
            try Task.checkCancellation()
            onStage?("Testing \(rung.label)")
            verdicts.append(try await judge(work: work, skill: skill, rung: rung, backend: backend))
        }

        // Walk down from the top. The first rung whose YES is backed by a
        // sentence that stands on its own is the placement.
        //
        // Highest-corroborated rather than count-the-leading-YESes because the
        // rungs aren't a staircase: an essay can analyse how a community used
        // an artwork (rung 4) without ever saying how the art made it feel
        // (rung 3). Counting from the bottom pinned that essay at 2.
        //
        // And backed by a real citation rather than trusting the YES, because
        // the YES alone is cheap: a thin piece answered YES at rung 4 citing
        // "I saw the mural on 14th Street." A rung whose evidence is that
        // slight doesn't get to set the level.
        let corroborated = verdicts
            .sorted { $0.ordinal > $1.ordinal }
            .first { verdict in
                guard verdict.meets == true,
                      let index = verdict.evidenceSentence,
                      let sentence = work.sentence(index) else { return false }
                return carriesWeight(sentence)
            }?
            .ordinal

        var placement = SkillPlacement(skillId: skill.id, verdicts: verdicts,
                                       corroboratedRung: corroborated, nextStep: nil)
        if let next = skill.rung(placement.level + 1),
           let current = skill.rung(placement.level) {
            try Task.checkCancellation()
            onStage?("Writing the next step")
            let evidence = placement.evidenceSentences.first.flatMap { work.sentence($0) }
            placement.nextStep = try await nextStep(current: current, next: next,
                                                   evidence: evidence, backend: backend)
        }
        return placement
    }

    /// Set by the probe to dump each stage's raw reply.
    static var traceRawReplies = false

    private static func trace(_ stage: String, _ reply: String) {
        guard traceRawReplies else { return }
        print("    « \(stage): \(reply.replacingOccurrences(of: "\n", with: " ").prefix(160))")
    }

    /// Does the cited sentence carry enough to be evidence of anything?
    ///
    /// Deliberately not a model call. Re-asking the model about the sentence
    /// alone was tried and is too severe — stripped of context it rejected
    /// sound citations too, and an essay that had been placing correctly at
    /// rung 4 collapsed to the floor. What actually separated a real citation
    /// from a reflex in the failing cases was substance: "I saw the mural on
    /// 14th Street" against a sentence carrying a whole clause of reasoning.
    ///
    /// Counting content words rather than characters so a long list of short
    /// filler words doesn't pass, and so punctuation doesn't decide it.
    static func carriesWeight(_ sentence: String) -> Bool {
        let stopwords: Set<String> = [
            "the", "and", "but", "for", "with", "that", "this", "there", "here",
            "was", "were", "are", "is", "it", "its", "a", "an", "of", "to",
            "in", "on", "at", "by", "from", "as", "i", "my", "me", "we", "you",
            "he", "she", "they", "them", "his", "her", "their", "some", "very",
            "too", "also", "like", "just", "so", "then", "than", "when", "what",
        ]
        let words = sentence
            .lowercased()
            .split { !$0.isLetter && !$0.isNumber }
            .map(String.init)
            .filter { $0.count >= 3 && !stopwords.contains($0) }
        return Set(words).count >= 6
    }

    static func judge(work: WorkDocument, skill: ComponentSkill, rung: ProgressionRung,
                      backend: ChatBackend) async throws -> RungVerdict {
        var options = GenerationOptions.extraction
        options.assistantPrefix = "{\"meets\":"
        let reply = try await backend.complete(
            turns: [ChatTurn(role: .system, content: EvaluationPrompts.system),
                    ChatTurn(role: .user, content: EvaluationPrompts.rung(work: work, skill: skill, rung: rung))],
            options: options)
        trace("rung \(rung.ordinal)", reply)

        guard let object = JSONRepair.object(from: reply) else {
            return RungVerdict(ordinal: rung.ordinal, meets: nil, evidenceSentence: nil)
        }
        let meets = readBool(object["meets"])
        var sentence = readInt(object["sentence"])
        // Out of range is a citation problem, not a placement problem: keep
        // the verdict, drop the pointer.
        if let n = sentence, work.sentence(n) == nil { sentence = nil }
        return RungVerdict(ordinal: rung.ordinal, meets: meets, evidenceSentence: sentence)
    }

    static func nextStep(current: ProgressionRung, next: ProgressionRung,
                         evidence: String?, backend: ChatBackend) async throws -> String? {
        let reply = try await backend.complete(
            turns: [ChatTurn(role: .system, content: EvaluationPrompts.system),
                    ChatTurn(role: .user, content: EvaluationPrompts.nextStep(
                        current: current, next: next, evidence: evidence))],
            options: .prose)
        let cleaned = reply.trimmingCharacters(in: .whitespacesAndNewlines)
        // The least load-bearing output in the pipeline — if it came back
        // empty, say nothing rather than showing a stub.
        return cleaned.isEmpty ? nil : cleaned
    }

    private static func readBool(_ value: Any?) -> Bool? {
        if let b = value as? Bool { return b }
        if let n = value as? NSNumber { return n.boolValue }
        if let s = value as? String {
            let lowered = s.lowercased()
            if lowered.hasPrefix("t") || lowered.hasPrefix("y") { return true }
            if lowered.hasPrefix("f") || lowered.hasPrefix("n") { return false }
        }
        return nil
    }

    private static func readInt(_ value: Any?) -> Int? {
        if let n = value as? NSNumber { return n.intValue }
        if let s = value as? String { return Int(s.trimmingCharacters(in: .whitespaces)) }
        return nil
    }
}
