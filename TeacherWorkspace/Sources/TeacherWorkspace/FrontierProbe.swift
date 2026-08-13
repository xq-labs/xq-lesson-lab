import Foundation

/// Headless checks for the frontier-review transport.
///
/// `RedactionProbe` proves nothing leaks; these prove the request is shaped
/// right, the failures read like English, and — with a real key — that the
/// round trip works.
enum FrontierProbe {

    /// TW_REVIEW_ERRORS=1 — print every failure a teacher could hit, with the
    /// exact words they'd see. The only practical way to eyeball a dozen
    /// strings that each appear once, in a state that's hard to reproduce.
    static func runErrors() -> Never {
        let provider = AnthropicDirectProvider()

        print("Failure messages — \(AppInfo.productName) second opinions\n")
        print(String(repeating: "─", count: 78))

        let cases: [(String, FrontierError)] = [
            ("no key configured", .noKey),
            ("gate blocked the payload", .blocked([])),
            ("offline", .offline),
            ("school firewall", .blockedByNetwork(host: provider.host)),
            ("bad key (401)", .unauthorized),
            ("rate limited, no hint (429)", .rateLimited(retryAfter: nil)),
            ("rate limited, retry-after (429)", .rateLimited(retryAfter: 40)),
            ("out of credit", .outOfCredit),
            ("servers overloaded (529)", .overloaded),
            ("model declined", .refused(category: "cyber")),
            ("cut short at max_tokens", .truncated),
            ("unexpected status", .badResponse(status: 418)),
            ("garbled reply", .malformed),
            ("teacher cancelled", .cancelled),
        ]
        for (name, error) in cases {
            print("\n\(name)\(error.isWorthRetrying ? "  [offer retry]" : "")")
            print("  \(error.errorDescription ?? "(no message)")")
            print("  → \(error.nextStep)")
        }

        print("\n" + String(repeating: "─", count: 78))
        print("\nURLError mapping:")
        let urlCases: [(String, URLError.Code)] = [
            ("notConnectedToInternet", .notConnectedToInternet),
            ("networkConnectionLost", .networkConnectionLost),
            ("cannotFindHost", .cannotFindHost),
            ("cannotConnectToHost", .cannotConnectToHost),
            ("secureConnectionFailed", .secureConnectionFailed),
            ("timedOut", .timedOut),
            ("cancelled", .cancelled),
        ]
        for (name, code) in urlCases {
            let mapped = FrontierError.from(urlError: URLError(code), host: provider.host)
            print("  \(name) → \(mapped.errorDescription ?? "?")")
        }

        // Every failure must leave the teacher somewhere to go. A dead end is
        // a bug in this feature, not a copy nitpick — it's the moment someone
        // decides the whole app is broken.
        let unhelpful = cases.filter { _, error in
            (error.errorDescription ?? "").isEmpty || error.nextStep.isEmpty
        }
        print("\n" + String(repeating: "─", count: 78))
        if unhelpful.isEmpty {
            print("\(cases.count) failures, every one says what happened and what to do next.")
            exit(0)
        }
        for (name, _) in unhelpful { print("✘ \(name) — dead end, no next step") }
        exit(1)
    }

    /// TW_KEYCHAIN_TEST=1 — store, read back, and delete a throwaway secret.
    ///
    /// Exists because the first version of `Keychain` set
    /// `kSecUseDataProtectionKeychain`, which needs an entitlement this app
    /// doesn't have, so every save failed with "A required entitlement isn't
    /// present." — and the only way to find that was to click through the
    /// setup sheet by hand. Now it's one command.
    static func runKeychainTest() -> Never {
        let item = Keychain.Item(service: "org.xqinstitute.lesson-lab.frontier.probe",
                                 account: "probe")
        let secret = "sk-ant-probe-value-not-a-real-key"
        var failed = false

        func check(_ name: String, _ ok: Bool, _ detail: String = "") {
            print("  \(ok ? "✓" : "✘") \(name)\(detail.isEmpty ? "" : " — \(detail)")")
            if !ok { failed = true }
        }

        print("Keychain round trip\n" + String(repeating: "─", count: 78))
        try? Keychain.delete(item)

        do {
            try Keychain.store(secret, in: item)
            check("store", true)
        } catch {
            check("store", false, error.localizedDescription)
            print("\nA save that fails here fails in the setup sheet too.")
            exit(1)
        }

        check("exists", Keychain.exists(item))
        check("read matches", Keychain.read(item) == secret)

        // Saving twice must update in place, not fail on errSecDuplicateItem —
        // this is the path a teacher takes when they paste a replacement key.
        do {
            try Keychain.store(secret + "-second", in: item)
            check("overwrite", Keychain.read(item) == secret + "-second")
        } catch {
            check("overwrite", false, error.localizedDescription)
        }

        do {
            try Keychain.delete(item)
            check("delete", Keychain.read(item) == nil)
        } catch {
            check("delete", false, error.localizedDescription)
        }
        // Deleting something that isn't there is a no-op, not an error.
        do {
            try Keychain.delete(item)
            check("delete when absent is a no-op", true)
        } catch {
            check("delete when absent is a no-op", false, error.localizedDescription)
        }

        print(String(repeating: "─", count: 78))
        print(failed ? "FAILED — the setup sheet would fail the same way."
                     : "Keychain works from this build.")
        exit(failed ? 1 : 0)
    }

    /// TW_REVIEW_PARSE=<file> — decode a canned API response the way the
    /// transport would. Ship fixtures for a refusal and a truncation; both
    /// return HTTP 200 and neither can be reproduced on demand.
    static func runParse(file: String) -> Never {
        guard let data = FileManager.default.contents(atPath: file) else {
            print("PARSE: can't read \(file)")
            exit(1)
        }
        do {
            let result = try AnthropicDirectProvider.parse(data)
            print("strengths (\(result.strengths.count)):")
            for s in result.strengths { print("  · \(s)") }
            print("\nsuggestions (\(result.suggestions.count)):")
            for s in result.suggestions {
                let step = s.stepNumber.map { " [step \($0)]" } ?? ""
                print("  · \(s.title)\(step)\n    \(s.detail)")
            }
            print("\nquestions (\(result.questions.count)):")
            for q in result.questions { print("  · \(q)") }
            exit(0)
        } catch {
            // A clean failure is a pass for the refusal and truncation
            // fixtures — the point is that it doesn't crash on content[0].
            print("PARSE stopped cleanly: \(error.localizedDescription)")
            exit(0)
        }
    }

    /// TW_REVIEW_BODY=<artifact id> — print the exact JSON request body,
    /// without sending it. Confirms the shape (no sampling parameters, schema
    /// present, model right) without spending a teacher's money.
    @MainActor
    static func runBody(artifactId: String) -> Never {
        let state = AppState()
        let lexicon = PIILexicon.build(from: state.classroom)
        guard let ref = state.findArtifactRef(id: artifactId),
              let markdown = ArtifactExport.markdown(for: ref, state: state),
              let title = state.artifact(for: ref)?.title else {
            print("BODY: no artifact with id \(artifactId)")
            exit(1)
        }
        do {
            let payload = try ReviewPayload(ref: ref, title: title, markdown: markdown,
                                            lexicon: lexicon)
            let provider = AnthropicDirectProvider()
            let body = try AnthropicDirectProvider.body(for: payload, model: provider.modelId)
            try RedactionGate.assertClean(body, lexicon: lexicon)

            print("POST https://\(provider.host)/v1/messages")
            print("  x-api-key: <from Keychain, never printed>")
            print("  anthropic-version: 2023-06-01")
            print("\n--- request body (\(body.count) bytes) — gate: clean ---")
            let pretty = try JSONSerialization.data(
                withJSONObject: JSONSerialization.jsonObject(with: body),
                options: [.prettyPrinted, .sortedKeys])
            print(String(decoding: pretty, as: UTF8.self))
            exit(0)
        } catch {
            print("BODY ERROR: \(error.localizedDescription)")
            exit(1)
        }
    }

    /// TW_REVIEW_LIVE=<artifact id> — the real thing. Needs TW_CLAUDE_KEY (or
    /// a configured Keychain entry). Point TW_FRONTIER_URL at a local echo
    /// server first.
    @MainActor
    static func runLive(artifactId: String) -> Never {
        let state = AppState()
        let lexicon = PIILexicon.build(from: state.classroom)
        guard let ref = state.findArtifactRef(id: artifactId),
              let markdown = ArtifactExport.markdown(for: ref, state: state),
              let title = state.artifact(for: ref)?.title else {
            print("LIVE: no artifact with id \(artifactId)")
            exit(1)
        }
        guard AnthropicDirectProvider.storedKey() != nil else {
            print("LIVE: no key — set TW_CLAUDE_KEY, or add one in the app")
            exit(1)
        }

        let payload: ReviewPayload
        do {
            payload = try ReviewPayload(ref: ref, title: title, markdown: markdown,
                                        lexicon: lexicon)
        } catch {
            print("LIVE: payload rejected — \(error.localizedDescription)")
            exit(1)
        }

        print("sending \(payload.byteCount) bytes about \"\(payload.subjectTitle)\"…")
        fflush(stdout)

        var status: Int32 = 0
        let semaphore = DispatchSemaphore(value: 0)
        let started = Date()
        Task.detached {
            do {
                let result = try await AnthropicDirectProvider().review(payload, lexicon: lexicon)
                let elapsed = Date().timeIntervalSince(started)
                print(String(format: "\nround trip: %.1fs\n", elapsed))
                print("strengths:")
                for s in result.strengths { print("  · \(s)") }
                print("\nsuggestions:")
                for s in result.suggestions {
                    print("  · \(s.title)\(s.stepNumber.map { " [step \($0)]" } ?? "")")
                    print("    \(s.detail)")
                }
                print("\nquestions:")
                for q in result.questions { print("  · \(q)") }
            } catch {
                print("\nLIVE FAILED: \(error.localizedDescription)")
                status = 1
            }
            semaphore.signal()
        }
        semaphore.wait()
        fflush(stdout)
        exit(status)
    }

    /// TW_AUDIT_DUMP=1 — print the audit log the way the viewer renders it.
    static func runAuditDump() -> Never {
        let entries = FrontierAuditLog.recent()
        guard !entries.isEmpty else {
            print("Nothing has ever been sent from this Mac.")
            exit(0)
        }
        for entry in entries {
            print("\(entry.at) · \(entry.phase) · \(entry.host)\(entry.path) · "
                  + "\(entry.modelId) · \(entry.requestBytes) bytes · \(entry.gateVerdict)")
            if let error = entry.error { print("    \(error)") }
            if let payload = entry.payload {
                print("    payload: \(payload.prefix(120))…")
            }
        }
        exit(0)
    }
}
