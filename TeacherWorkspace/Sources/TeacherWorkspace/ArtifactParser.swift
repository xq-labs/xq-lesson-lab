import Foundation

/// Parses the model's streamed reply for fenced artifact blocks:
///
/// ```artifact
/// {"type": "rubric", "title": ...}
/// ```
///
/// The parser re-scans the full raw text on every delta (replies are a few KB
/// at most) and returns the user-visible text with artifact blocks removed,
/// plus any completed artifacts and whether a block is still streaming.
enum ArtifactParser {

    struct Result {
        var visibleText: String
        var artifacts: [ParsedArtifact]
        var isDraftingArtifact: Bool
        /// A block looked like one of our artifacts but couldn't be parsed
        /// even after repair. The JSON stays hidden either way; this flag is
        /// how the UI avoids presenting that as an empty reply.
        var hadUnparseableArtifact = false
    }

    enum ParsedArtifact {
        case rubric(Rubric)
        case activity(Activity)
        case pog(Pog)
        case quiz(Quiz)
        case email(EmailDraft)

        var ref: (type: ArtifactType, id: String) {
            switch self {
            case .rubric(let r): return (.rubric, r.id)
            case .activity(let a): return (.activity, a.id)
            case .pog(let p): return (.pog, p.id)
            case .quiz(let q): return (.quiz, q.id)
            case .email(let e): return (.email, e.id)
            }
        }
    }

    /// `final` marks the end of the stream: an unterminated artifact block is
    /// "drafting" while tokens are still coming, but once the reply is over it
    /// gets one repair attempt (the model hit its token ceiling or lost the
    /// closing fence) and is flagged if that fails — never silently dropped.
    static func process(_ raw: String, idPrefix: String, final: Bool = false) -> Result {
        var visible = ""
        var artifacts: [ParsedArtifact] = []
        var drafting = false
        var unparseable = false

        var rest = Substring(raw)
        while let fenceStart = rest.range(of: "```") {
            visible += rest[..<fenceStart.lowerBound]
            let afterFence = rest[fenceStart.upperBound...]
            guard let fenceEnd = afterFence.range(of: "```") else {
                // Unterminated block. If it looks like an artifact (or is still
                // too short to tell), hide it and flag drafting; otherwise it's
                // ordinary code — show it raw.
                let body = String(afterFence)
                if final, isLikelyArtifactBlock(body) {
                    // The stream ended inside the block — repair it or say so.
                    if let artifact = parseArtifact(body, idPrefix: idPrefix, index: artifacts.count) {
                        artifacts.append(artifact)
                    } else if let salvaged = salvageText(body) {
                        visible += salvaged
                    } else {
                        unparseable = true
                    }
                } else if !final, isLikelyArtifactBlock(body) || body.count < 24 {
                    drafting = true
                } else {
                    visible += "```" + body
                }
                rest = Substring("")
                break
            }
            let body = String(afterFence[..<fenceEnd.lowerBound])
            if isLikelyArtifactBlock(body) {
                if let artifact = parseArtifact(body, idPrefix: idPrefix, index: artifacts.count) {
                    artifacts.append(artifact)
                } else if let salvaged = salvageText(body) {
                    // The model wrapped a plain answer in an artifact block
                    // (e.g. {"type":"other","text":…}) — surface the text.
                    visible += salvaged
                } else {
                    // Tagged as artifact but unparseable — hide the JSON and
                    // flag it, so the bubble can say so instead of sitting empty.
                    unparseable = true
                }
            } else {
                visible += "```" + body + "```"
            }
            rest = afterFence[fenceEnd.upperBound...]
        }
        visible += rest

        // Small models sometimes skip the fence entirely and emit the JSON
        // inline. Detect a bare {"type":"<ours>"…} object in the visible text.
        (visible, drafting) = extractBareJSON(
            from: visible, into: &artifacts, idPrefix: idPrefix,
            drafting: drafting, final: final, unparseable: &unparseable)

        return Result(
            visibleText: visible.trimmingCharacters(in: .whitespacesAndNewlines),
            artifacts: artifacts,
            isDraftingArtifact: drafting,
            hadUnparseableArtifact: unparseable)
    }

    /// Finds an unfenced artifact JSON object, parses it, and removes it from
    /// the visible text. Returns the cleaned text and updated drafting flag.
    private static func extractBareJSON(
        from text: String, into artifacts: inout [ParsedArtifact],
        idPrefix: String, drafting: Bool, final: Bool, unparseable: inout Bool
    ) -> (String, Bool) {
        guard let typeRange = text.range(of: #"\{\s*"type"\s*:\s*"(rubric|activity|pog|quiz|email)""#,
                                         options: .regularExpression) else {
            return (text, drafting)
        }
        let start = typeRange.lowerBound
        let tail = String(text[start...])

        // Walk to where the object closes (string-aware).
        var depth = 0
        var inString = false
        var escaped = false
        var end: String.Index? = nil
        var i = tail.startIndex
        while i < tail.endIndex {
            let ch = tail[i]
            if escaped { escaped = false }
            else if inString {
                if ch == "\\" { escaped = true } else if ch == "\"" { inString = false }
            } else {
                if ch == "\"" { inString = true }
                else if ch == "{" { depth += 1 }
                else if ch == "}" { depth -= 1; if depth == 0 { end = i; break } }
            }
            i = tail.index(after: i)
        }

        var cleaned = String(text[..<start])
        if let end {
            let body = String(tail[...end])
            if let artifact = parseArtifact(body, idPrefix: idPrefix, index: artifacts.count) {
                artifacts.append(artifact)
            } else {
                unparseable = true
            }
            cleaned += String(tail[tail.index(after: end)...])
            return (cleaned, drafting)
        }
        // Object never closed. Mid-stream that means still drafting; at the
        // end of the stream it gets the same repair-or-flag treatment as an
        // unterminated fenced block.
        if final {
            if let artifact = parseArtifact(tail, idPrefix: idPrefix, index: artifacts.count) {
                artifacts.append(artifact)
            } else {
                unparseable = true
            }
            return (cleaned, drafting)
        }
        return (cleaned, true)
    }

    /// For artifact-tagged blocks with an unrecognized type: pull out any
    /// human-readable text so the reply isn't silently swallowed.
    private static func salvageText(_ body: String) -> String? {
        var jsonText = body
        if let newline = jsonText.firstIndex(of: "\n"), !jsonText.hasPrefix("{") {
            jsonText = String(jsonText[jsonText.index(after: newline)...])
        }
        guard let start = jsonText.firstIndex(of: "{"),
              let obj = JSONRepair.object(from: String(jsonText[start...])) else { return nil }
        for key in ["text", "content", "message", "description"] {
            if let s = obj[key] as? String, !s.isEmpty { return s }
        }
        return nil
    }

    private static func isLikelyArtifactBlock(_ body: String) -> Bool {
        let head = body.prefix(200)
        if head.hasPrefix("artifact") { return true }
        // Models sometimes tag it ```json or leave the tag off entirely —
        // accept any fenced JSON whose "type" is one of ours.
        return head.contains("\"type\"")
            && (head.contains("\"rubric\"") || head.contains("\"activity\"") || head.contains("\"pog\"")
                || head.contains("\"quiz\"") || head.contains("\"email\""))
    }

    private static func parseArtifact(_ body: String, idPrefix: String, index: Int) -> ParsedArtifact? {
        // Strip a leading tag line ("artifact" / "json") before the JSON.
        var jsonText = body
        if let newline = jsonText.firstIndex(of: "\n"), !jsonText.hasPrefix("{") {
            jsonText = String(jsonText[jsonText.index(after: newline)...])
        }
        guard let start = jsonText.firstIndex(of: "{") else { return nil }
        let candidate = String(jsonText[start...]).trimmingCharacters(in: .whitespacesAndNewlines)
        guard let obj = JSONRepair.object(from: candidate),
              let type = obj["type"] as? String else { return nil }

        let id = "\(idPrefix)-\(index)"
        let title = (obj["title"] as? String)?.trimmingCharacters(in: .whitespaces) ?? "Untitled"

        switch type {
        case "rubric":
            guard let rawCriteria = obj["criteria"] as? [[String: Any]], !rawCriteria.isEmpty else { return nil }
            let criteria = rawCriteria.compactMap { c -> RubricCriterion? in
                guard let name = c["name"] as? String else { return nil }
                var levels = (c["levels"] as? [String]) ?? []
                while levels.count < 4 { levels.append("—") }
                return RubricCriterion(name: name, cells: Array(levels.prefix(4)))
            }
            guard !criteria.isEmpty else { return nil }
            let rubric = Rubric(
                id: id, title: title,
                sub: obj["subtitle"] as? String ?? "Drafted in chat",
                meta: "\(criteria.count) criteria · Created in chat",
                criteria: criteria)
            return .rubric(rubric)

        case "activity":
            let steps = (obj["steps"] as? [String]) ?? []
            guard !steps.isEmpty else { return nil }
            let subject = obj["subject"] as? String ?? "General"
            let duration = obj["duration"] as? String ?? "45 min"
            let format = obj["format"] as? String ?? "Activity"
            let activity = Activity(
                id: id, title: title,
                meta: "\(subject) · \(duration) · \(format)",
                desc: obj["description"] as? String ?? "Drafted in chat",
                steps: steps)
            return .activity(activity)

        case "pog":
            guard let rawComps = obj["competencies"] as? [[String: Any]], !rawComps.isEmpty else { return nil }
            let comps = rawComps.compactMap { c -> PogCompetency? in
                guard let name = c["name"] as? String else { return nil }
                let level = (c["level"] as? Int) ?? (c["level"] as? Double).map(Int.init) ?? 3
                return PogCompetency(
                    name: name,
                    desc: c["description"] as? String ?? "",
                    level: min(5, max(1, level)))
            }
            guard !comps.isEmpty else { return nil }
            let pog = Pog(
                id: id, title: title,
                sub: obj["subtitle"] as? String ?? "Drafted in chat",
                meta: "\(comps.count) competencies · Created in chat",
                comps: comps)
            return .pog(pog)

        case "quiz":
            guard let rawQuestions = obj["questions"] as? [[String: Any]], !rawQuestions.isEmpty else { return nil }
            let questions = rawQuestions.compactMap { q -> QuizQuestion? in
                guard let prompt = (q["prompt"] as? String) ?? (q["question"] as? String) else { return nil }
                return QuizQuestion(
                    prompt: prompt,
                    choices: (q["choices"] as? [String]) ?? (q["options"] as? [String]) ?? [],
                    answer: (q["answer"] as? String) ?? "")
            }
            guard !questions.isEmpty else { return nil }
            let quiz = Quiz(
                id: id, title: title,
                sub: obj["subtitle"] as? String ?? "Drafted in chat",
                meta: "\(questions.count) question\(questions.count == 1 ? "" : "s") · Created in chat",
                questions: questions)
            return .quiz(quiz)

        case "email":
            guard let body = (obj["body"] as? String) ?? (obj["text"] as? String),
                  !body.trimmingCharacters(in: .whitespaces).isEmpty else { return nil }
            let subject = (obj["subject"] as? String) ?? title
            let email = EmailDraft(
                id: id, title: subject,
                sub: obj["subtitle"] as? String ?? "Family communication",
                meta: "Email draft · Created in chat",
                body: body)
            return .email(email)

        default:
            return nil
        }
    }
}
