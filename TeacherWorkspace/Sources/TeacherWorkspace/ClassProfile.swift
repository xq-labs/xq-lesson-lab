import Foundation

/// A class described in counts rather than in children.
///
/// This is the local model's entire job in a frontier review, and the shape of
/// this type is what makes that job safe. The model is never asked to write
/// prose that gets sent; it is asked which of seven fixed categories a note
/// falls into, and it answers with a number. A student's name is not
/// representable in that answer — the same move `WorkDocument` makes by asking
/// for a sentence index instead of a quotation.
///
/// Swift does the tallying and writes the sentence that actually leaves.
struct ClassProfile: Codable, Equatable {

    /// The closed vocabulary. Adding a case is a deliberate act; the model can
    /// only ever pick from what is here.
    enum NeedCategory: Int, CaseIterable, Codable {
        case readingSupport = 1
        case languageSupport
        case extensionWork
        case attendanceGap
        case engagement
        case accessibility
        case none

        /// What the model is shown, and what the outgoing sentence says.
        var label: String {
            switch self {
            case .readingSupport: return "reading or writing support"
            case .languageSupport: return "English language support"
            case .extensionWork: return "extension or challenge work"
            case .attendanceGap: return "catching up after missed time"
            case .engagement: return "engagement or motivation support"
            case .accessibility: return "an accessibility accommodation"
            case .none: return "no particular need noted"
            }
        }
    }

    /// Counts of 1 or 2 are written as "a few" rather than as a number.
    ///
    /// In a class of six, "1 student with an accessibility accommodation" names
    /// a child as surely as writing the name would. Not adjustable — a
    /// threshold a user can lower is a threshold that gets lowered.
    static let smallCellThreshold = 2

    var studentCount: Int
    var gradeLevel: String
    var subject: String
    /// `NeedCategory.rawValue` -> how many students.
    var needCounts: [Int: Int]

    /// The one line that actually goes into the payload. Composed here, in
    /// Swift, from the tallies — no model-generated text reaches the network.
    var summaryLine: String {
        var parts: [String] = ["\(studentCount) student\(studentCount == 1 ? "" : "s")"]
        if !gradeLevel.isEmpty { parts[0] += ", \(gradeLevel)" }
        if !subject.isEmpty { parts[0] += ", \(subject.lowercased())" }

        let described = NeedCategory.allCases
            .filter { $0 != .none }
            .compactMap { category -> String? in
                guard let count = needCounts[category.rawValue], count > 0 else { return nil }
                let quantity = count <= Self.smallCellThreshold ? "a few" : "\(count)"
                return "\(quantity) needing \(category.label)"
            }
        if described.isEmpty { return parts[0] + "." }
        return parts[0] + " — " + described.joined(separator: ", ") + "."
    }
}

/// Turns a roster into a `ClassProfile` using the on-device model, one small
/// call per student.
///
/// Sequential on purpose: `LlamaBackend` runs a single serial queue, so issuing
/// these concurrently would buy no parallelism and only interleave with chat.
/// Same reasoning as `EvaluationPipeline`.
enum ClassProfiler {

    static func profile(_ section: ClassSection,
                        subject: String,
                        backend: ChatBackend,
                        onStage: ((String) -> Void)? = nil) async throws -> ClassProfile {
        let roster = section.students.filter { !$0.name.isEmpty }
        var counts: [Int: Int] = [:]

        for (index, student) in roster.enumerated() {
            try Task.checkCancellation()
            // A student with no note needs no call — and asking the model to
            // categorise an empty string is how you get a category back that
            // nobody wrote down.
            guard !student.notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                counts[ClassProfile.NeedCategory.none.rawValue, default: 0] += 1
                continue
            }
            onStage?("Summarising the class (\(index + 1) of \(roster.count))")
            let category = try await categorise(note: student.notes, backend: backend)
            counts[category.rawValue, default: 0] += 1
        }

        return ClassProfile(studentCount: roster.count,
                            gradeLevel: section.gradeLevel,
                            subject: subject,
                            needCounts: counts)
    }

    /// Set by the probe to dump each raw reply.
    static var traceRawReplies = false

    static func categorise(note: String, backend: ChatBackend) async throws -> ClassProfile.NeedCategory {
        var options = GenerationOptions.extraction
        options.assistantPrefix = "{\"need\":"
        let reply = try await backend.complete(
            turns: [ChatTurn(role: .system, content: ProfilePrompts.system),
                    ChatTurn(role: .user, content: ProfilePrompts.categorise(note: note))],
            options: options)
        if traceRawReplies {
            print("    « \(reply.replacingOccurrences(of: "\n", with: " ").prefix(120))")
        }

        guard let object = JSONRepair.object(from: reply),
              let raw = readInt(object["need"]),
              let category = ClassProfile.NeedCategory(rawValue: raw)
        else {
            // An unreadable answer counts as nothing noted. Guessing a category
            // would put a claim about a real classroom into the payload on the
            // strength of a malformed reply.
            return .none
        }
        return category
    }

    private static func readInt(_ value: Any?) -> Int? {
        if let n = value as? NSNumber { return n.intValue }
        if let s = value as? String { return Int(s.trimmingCharacters(in: .whitespaces)) }
        return nil
    }
}

/// Deliberately not `AppState.systemPrompt` — that prompt's artifact contract
/// is strong enough to turn "answer with a number" into a generated quiz. Same
/// reason `EvaluationPrompts` keeps its own.
enum ProfilePrompts {
    static let system = """
        You are a careful assistant that sorts short teacher notes into fixed \
        categories. You answer only with the JSON asked for — no preamble, no \
        explanation, no names.
        """

    static func categorise(note: String) -> String {
        let options = ClassProfile.NeedCategory.allCases
            .map { "\($0.rawValue) = \($0.label)" }
            .joined(separator: "\n")
        return """
            TEACHER'S NOTE ABOUT ONE STUDENT:
            \(note)

            CATEGORIES:
            \(options)

            Which single category best fits this note? If none clearly fits, \
            answer \(ClassProfile.NeedCategory.none.rawValue).
            Answer only this JSON:
            {"need": <the category number>}
            """
    }
}
