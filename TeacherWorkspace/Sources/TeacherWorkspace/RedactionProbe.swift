import Foundation

/// Headless checks for the de-identification gate.
///
/// This is the FERPA argument in executable form. Everything else about the
/// frontier-review feature is a promise made in copy; `TW_REDACT_ADVERSARIAL`
/// is the promise made in a process exit code, and it runs before any code
/// that can open a socket exists in the binary.
enum RedactionProbe {

    /// TW_REDACT_TEST="<text>" — redact one string against the demo classroom
    /// and print what happened. Exits non-zero if the gate finds a leak in the
    /// redactor's own output, which would mean the two disagree.
    static func runSingle(_ text: String) -> Never {
        let lexicon = PIILexicon.build(from: .demo)
        let result = Deidentifier.process(text, lexicon: lexicon)

        print("lexicon: \(lexicon.tokens.count) tokens, \(lexicon.pseudonyms.count) pseudonyms")
        print("\n--- in ---\n\(text)")
        print("\n--- out ---\n\(result.text)")

        print("\nremoved:")
        for r in result.redactions {
            print("  \(r.original) → \(r.replacement)\(r.count > 1 ? " (×\(r.count))" : "")")
        }
        if result.redactions.isEmpty { print("  (nothing)") }

        if !result.flagged.isEmpty {
            print("\nleft in place (ordinary words that are also names):")
            for r in result.flagged { print("  \(r.original)") }
        }

        let findings = RedactionGate.verify(result.text, lexicon: lexicon)
        let blocking = findings.filter(\.isBlocking)
        print("\ngate: \(blocking.isEmpty ? "clean" : "BLOCKED")")
        for f in findings { print("  \(f.isBlocking ? "✘" : "·") \(f.message)") }
        exit(blocking.isEmpty ? 0 : 1)
    }

    /// TW_REDACT_ADVERSARIAL=1 — the regression corpus. Each case says what
    /// must happen to it; any disagreement fails the build.
    static func runAdversarial() -> Never {
        let lexicon = PIILexicon.build(from: .demo)
        var failures = 0

        print("Redaction gate — adversarial corpus (demo classroom)\n")
        print(String(repeating: "─", count: 78))

        for probe in corpus {
            let result = Deidentifier.process(probe.input, lexicon: lexicon)
            let blocking = RedactionGate.verify(result.text, lexicon: lexicon).filter(\.isBlocking)

            var problems: [String] = []
            for needle in probe.mustRemove where result.text.localizedCaseInsensitiveContains(needle) {
                problems.append("LEAKED \"\(needle)\"")
            }
            for needle in probe.mustKeep where !result.text.contains(needle) {
                problems.append("over-redacted \"\(needle)\"")
            }
            if !blocking.isEmpty { problems.append("gate blocked its own output") }

            let ok = problems.isEmpty
            if !ok { failures += 1 }
            print("\(ok ? "✓" : "✘") \(probe.name)")
            print("    \(result.text.replacingOccurrences(of: "\n", with: " ⏎ "))")
            for problem in problems { print("    → \(problem)") }
        }

        print(String(repeating: "─", count: 78))
        print(failures == 0
              ? "\(corpus.count) cases, all clean."
              : "\(failures) of \(corpus.count) cases FAILED — do not ship.")
        exit(failures == 0 ? 0 : 1)
    }

    /// TW_REVIEW_PAYLOAD=<artifact id> — build the payload that a frontier
    /// review would send and print the exact bytes. No network stack is
    /// touched, and none needs to exist for this to be the honest answer to
    /// "what would leave my Mac?".
    ///
    /// Wrap it in a shell assertion that greps for every roster name; that
    /// assertion is the FERPA argument, and it runs in under a second.
    @MainActor
    static func runPayload(artifactId: String) -> Never {
        let state = AppState()
        let lexicon = PIILexicon.build(from: state.classroom)

        guard let ref = state.findArtifactRef(id: artifactId) else {
            print("PAYLOAD: no artifact with id \(artifactId)")
            print("known ids: " + state.allReviewableRefs.map(\.id).joined(separator: ", "))
            exit(1)
        }
        guard let markdown = ArtifactExport.markdown(for: ref, state: state),
              let title = state.artifact(for: ref)?.title else {
            print("PAYLOAD: \(artifactId) could not be rendered")
            exit(1)
        }

        do {
            let payload = try ReviewPayload(ref: ref, title: title, markdown: markdown,
                                            lexicon: lexicon)
            print("artifact: \(ref.type.rawValue) \(ref.id)")
            print("lexicon: \(lexicon.tokens.count) tokens")
            print("\nremoved:")
            for r in payload.redactions {
                print("  \(r.original) → \(r.replacement)\(r.count > 1 ? " (×\(r.count))" : "")")
            }
            if payload.redactions.isEmpty { print("  (nothing)") }
            for r in payload.flagged { print("  · left in place: \(r.original)") }
            for f in payload.advisories { print("  · \(f.message)") }

            print("\n--- exactly what would be sent (\(payload.byteCount) bytes) ---")
            print(payload.outgoingText)
            print("--- end ---")
            exit(0)
        } catch let blocked as RedactionGate.Blocked {
            print("PAYLOAD BLOCKED — nothing would be sent")
            for f in blocked.findings { print("  ✘ \(f.message)") }
            exit(1)
        } catch {
            print("PAYLOAD ERROR: \(error.localizedDescription)")
            exit(1)
        }
    }

    // MARK: - The corpus

    private struct Probe {
        var name: String
        var input: String
        /// Must not appear anywhere in the output.
        var mustRemove: [String] = []
        /// Must survive — the guard against a redactor that shreds ordinary prose.
        var mustKeep: [String] = []
    }

    private static let corpus: [Probe] = [
        Probe(name: "plain full name",
              input: "Maya Rodriguez needs a scaffold for the inference question.",
              mustRemove: ["Maya", "Rodriguez"],
              mustKeep: ["scaffold"]),

        Probe(name: "possessive with apostrophe",
              input: "Check Maya's exit ticket before Friday.",
              mustRemove: ["Maya"],
              mustKeep: ["exit ticket"]),

        Probe(name: "possessive with curly apostrophe",
              input: "Jamal\u{2019}s group finished early.",
              mustRemove: ["Jamal"],
              mustKeep: ["group finished early"]),

        Probe(name: "bare plural",
              input: "The Rodriguezs sat together.",
              mustRemove: ["Rodriguez"]),

        Probe(name: "lowercase",
              input: "pair maya with jamal for the debate.",
              mustRemove: ["maya", "jamal"],
              mustKeep: ["debate"]),

        Probe(name: "diacritic variant of a plain roster name",
              input: "Sofía came back from her absence today.",
              mustRemove: ["Sofía", "Sofia"],
              mustKeep: ["absence"]),

        Probe(name: "name split across a newline",
              input: "Talk to Sofia\nKim about the make-up lab.",
              mustRemove: ["Sofia", "Kim"],
              mustKeep: ["make-up lab"]),

        // The false-positive guard. A redactor that fails this one is worse
        // than no redactor, because teachers stop reading the payload.
        Probe(name: "name as a substring must NOT match",
              input: "Mayapple grows in the shade; Kimchi is fermented cabbage.",
              mustKeep: ["Mayapple", "Kimchi"]),

        Probe(name: "teacher and school",
              input: "Dana Alvarez teaches this at Crestview High.",
              mustRemove: ["Dana", "Alvarez", "Crestview"]),

        Probe(name: "class section name",
              input: "Period 2 · Biology meets after lunch.",
              mustRemove: ["Period 2 · Biology"],
              mustKeep: ["after lunch"]),

        Probe(name: "email address",
              input: "Send it to dana.alvarez@crestview.k12.us before Monday.",
              mustRemove: ["dana.alvarez@crestview.k12.us", "@crestview"],
              mustKeep: ["before Monday"]),

        Probe(name: "phone number",
              input: "The family can be reached at (555) 213-9987 after 4pm.",
              mustRemove: ["555", "9987"],
              mustKeep: ["after 4pm"]),

        Probe(name: "student ID number",
              input: "Student number 4820117 is missing from the export.",
              mustRemove: ["4820117"],
              mustKeep: ["missing from the export"]),

        Probe(name: "home directory path",
              input: "Loaded from /Users/dana/Documents/plans.md this morning.",
              mustRemove: ["/Users/dana", "dana"],
              mustKeep: ["this morning"]),

        Probe(name: "years and page ranges survive",
              input: "Read pages 112-118, then compare the 1953 and 2019 models.",
              mustKeep: ["112-118", "1953", "2019"]),

        Probe(name: "two students keep distinct pseudonyms",
              input: "Maya presents first, then Jamal, then Maya again.",
              mustRemove: ["Maya", "Jamal"],
              mustKeep: ["presents first"]),

        Probe(name: "name buried in a numbered step",
              input: "1. Model the process.\n2. Have Jamal Carter demo it.\n3. Debrief.",
              mustRemove: ["Jamal", "Carter"],
              mustKeep: ["Debrief"]),

        Probe(name: "ordinary prose with no names at all",
              input: "Students annotate the diagram, then compare with a partner.",
              mustKeep: ["annotate the diagram", "compare with a partner"]),
    ]
}
