import Foundation

/// Prompts for the evaluation stages.
///
/// None of these use `AppState.systemPrompt`. That prompt carries a 25-line
/// contract instructing the model to emit artifact JSON, and it is strong
/// enough to turn "answer 1-4" into a generated quiz — measured, not feared.
/// Each stage gets a two-sentence system prompt and nothing else.
enum EvaluationPrompts {
    static let system = """
        You are a careful assessment assistant. You answer exactly in the \
        format asked for, with no preamble, no explanation, and no code blocks.
        """

    /// XQ writes progressions in the student's own voice ("I can identify
    /// art…"). Asking the model to read that as a description of someone else,
    /// mid-judgment, wastes the attention we need for the judgment. Swap the
    /// pronouns mechanically instead — deterministic, and the displayed text
    /// stays the verbatim original.
    static func thirdPerson(_ descriptor: String) -> String {
        var out = descriptor
        let swaps: [(String, String)] = [
            ("\\bI can\\b", "They can"),
            ("\\bI am\\b", "They are"),
            ("\\bI'm\\b", "They're"),
            ("\\bI\\b", "they"),
            ("\\bmy\\b", "their"),
            ("\\bMy\\b", "Their"),
            ("\\bmyself\\b", "themselves"),
            ("\\bmine\\b", "theirs"),
            ("\\bme\\b", "them"),
        ]
        for (pattern, replacement) in swaps {
            out = out.replacingOccurrences(of: pattern, with: replacement,
                                           options: [.regularExpression])
        }
        // A leading "they" reads better capitalized.
        if out.hasPrefix("they ") { out = "They " + out.dropFirst("they ".count) }
        return out
    }

    /// Is there anything here to judge at all? Keeps a lab report off an arts
    /// progression before any level gets assigned to it.
    static func relevance(work: WorkDocument, skill: ComponentSkill) -> String {
        """
        STUDENT WORK (numbered sentences):
        \(work.numbered)

        SKILL: \(skill.competencyName) — \(skill.name)
        WHAT IT MEANS: \(skill.detail)

        Could this piece of student work be judged against this skill at all?
        Answer NO if the work is about a different subject, or if it never \
        touches what this skill is about.
        Answer with one word: YES or NO.
        """
    }

    /// One rung, one question. The model never sees the four descriptors
    /// together — choosing among them at once is what produced the unstable
    /// answers this design exists to avoid.
    static func rung(work: WorkDocument, skill: ComponentSkill, rung: ProgressionRung) -> String {
        """
        STUDENT WORK (numbered sentences):
        \(work.numbered)

        SKILL: \(skill.competencyName) — \(skill.name)
        STATEMENT: \(thirdPerson(rung.descriptor))

        Answer true only if one specific sentence of the student work above \
        clearly shows the student doing what the STATEMENT describes. If the \
        work is about a different subject, or only brushes past it, answer false.
        Answer only this JSON:
        {"meets": true or false, "sentence": <the number of the ONE sentence that shows it, or 0>}
        """
    }

    /// Written from two descriptors and one real sentence — never the whole
    /// piece, which is both cheaper and keeps the advice anchored.
    static func nextStep(current: ProgressionRung, next: ProgressionRung, evidence: String?) -> String {
        var prompt = """
            The student is at this level: \(thirdPerson(current.descriptor))
            The next level is: \(thirdPerson(next.descriptor))
            """
        if let evidence {
            prompt += "\n\nThis is what they wrote that showed the current level:\n\"\(evidence)\""
        }
        prompt += """


            Write ONE sentence, addressed to the teacher, saying what this student \
            would need to do to reach the next level. Start with "To move toward". \
            No list, no preamble.
            """
        return prompt
    }
}
