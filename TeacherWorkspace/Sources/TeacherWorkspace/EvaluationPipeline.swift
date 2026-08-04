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
    var isRelevant: Bool
    var verdicts: [RungVerdict]
    var nextStep: String?

    /// Level 1 is the floor, so the ladder only asks about 2 upward, and the
    /// level is however far the YESes run without a break.
    var level: Int {
        var level = 1
        for verdict in verdicts.sorted(by: { $0.ordinal < $1.ordinal }) {
            guard verdict.meets == true else { break }
            level = verdict.ordinal
        }
        return level
    }

    /// A YES above a NO. The ladder came back incoherent, which is real
    /// information about how marginal the placement is — surfaced, not hidden.
    var hasMixedEvidence: Bool {
        let ordered = verdicts.sorted { $0.ordinal < $1.ordinal }
        guard let firstNo = ordered.firstIndex(where: { $0.meets != true }) else { return false }
        return ordered[firstNo...].contains { $0.meets == true }
    }

    /// Sentence numbers backing the level actually assigned.
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
    /// Placing one skill: 1 relevance call + one call per rung above the
    /// floor + 1 next-step call.
    static func evaluate(work: WorkDocument,
                         skill: ComponentSkill,
                         backend: ChatBackend,
                         onStage: ((String) -> Void)? = nil) async throws -> SkillPlacement {
        onStage?("Checking whether this skill applies")
        // Advisory, never a gate. Skipping the ladder on a NO threw away thin
        // work from struggling students — the very placements a teacher most
        // needs — so the answer becomes a caveat shown beside the result and
        // the rungs get asked either way.
        let relevant = try await isRelevant(work: work, skill: skill, backend: backend)

        var verdicts: [RungVerdict] = []
        for rung in skill.progression.sorted(by: { $0.ordinal < $1.ordinal }) where rung.ordinal > 1 {
            try Task.checkCancellation()
            onStage?("Testing \(rung.label)")
            verdicts.append(try await judge(work: work, skill: skill, rung: rung, backend: backend))
        }

        var placement = SkillPlacement(skillId: skill.id, isRelevant: relevant,
                                       verdicts: verdicts, nextStep: nil)
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

    static func isRelevant(work: WorkDocument, skill: ComponentSkill,
                           backend: ChatBackend) async throws -> Bool {
        let reply = try await backend.complete(
            turns: [ChatTurn(role: .system, content: EvaluationPrompts.system),
                    ChatTurn(role: .user, content: EvaluationPrompts.relevance(work: work, skill: skill))],
            options: .shortAnswer)
        trace("relevance", reply)
        // Read the first letter rather than demanding the exact word — and
        // treat anything else as "yes, keep going", since dropping a skill on
        // an unreadable answer hides the skill entirely.
        let first = reply.trimmingCharacters(in: .whitespacesAndNewlines).lowercased().first
        return first != "n"
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
