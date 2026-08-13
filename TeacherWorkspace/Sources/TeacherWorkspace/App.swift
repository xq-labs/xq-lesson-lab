import SwiftUI

@MainActor private var _snapshotState: AppState?
@MainActor private var _micTestController: DictationController?

@main
struct LessonLabApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var state = AppState()

    init() {
        // Snapshot mode for automated UI verification:
        // TW_SNAPSHOT=<out.png> [TW_THEME=light] [TW_SETTINGS=1] [TW_MODEL_PICKER=1] [TW_VIEW=rubrics|activities|pogs|integrations|models|welcome|onboarding] [TW_PREVIEW=rubric|activity|pog]
        // The app launches normally, configures state, captures its own window
        // after the first frame, writes the PNG, and exits.
        let env = ProcessInfo.processInfo.environment

        // Parser test: TW_PARSE_FILE=<path> runs ArtifactParser on the file
        // contents and prints the outcome.
        if let file = env["TW_PARSE_FILE"], let raw = try? String(contentsOfFile: file, encoding: .utf8) {
            let result = ArtifactParser.process(raw, idPrefix: "test")
            print("visible: \(result.visibleText.prefix(120))")
            print("drafting: \(result.isDraftingArtifact)")
            for a in result.artifacts { print("artifact: \(a.ref)") }
            exit(0)
        }

        // Store compatibility check: TW_STORE_CHECK=1 (with TW_STORE=<path>)
        // loads a store and prints what survived. Adding a non-optional field
        // to PersistedState makes the whole document fail to decode and takes
        // a teacher's chats and classroom with it, so every release that
        // touches that struct should run this against an older store.
        // TW_STORE_FUTURE=1 asserts a store written by a *later* version still
        // decodes — the mirror of TW_STORE_CHECK, which asserts an older one does.
        if env["TW_STORE_FUTURE"] != nil {
            PersistenceStore.runFutureCompatibilityCheck()
        }
        if env["TW_STORE_CHECK"] != nil {
            guard let saved = PersistenceStore.load() else {
                print("STORE: nothing decoded — a teacher on this build would lose everything")
                exit(1)
            }
            print("chats: \(saved.extraChats.count)")
            print("messages: \(saved.extraMessages.values.reduce(0) { $0 + $1.count })")
            print("rubrics: \(saved.userRubrics.count), activities: \(saved.userActivities.count), "
                  + "pogs: \(saved.userPogs.count), quizzes: \(saved.userQuizzes.count), "
                  + "emails: \(saved.userEmails.count)")
            print("folders: \(saved.folders?.count ?? 0), archived: \(saved.archivedChats?.count ?? 0)")
            print("classroom: \(saved.classroom.teacherName.isEmpty ? "(unnamed)" : saved.classroom.teacherName) "
                  + "— \(saved.classroom.classes.count) classes, "
                  + "\(saved.classroom.classes.reduce(0) { $0 + $1.students.count }) students")
            print("skill checks: \(saved.skillEvaluations?.count ?? 0)")
            print("second opinions: \(saved.frontierReviews?.compactMap(\.value).count ?? 0)")
            exit(0)
        }

        // Evaluation probe: TW_EVAL_FILE=<student work> TW_EVAL_SKILL=<skill id>
        // [TW_EVAL_RUNS=n] places the work on that skill's progression n times
        // and reports the spread. The spread is the point — a placement that
        // moves between runs is not a judgment, and this is the check that
        // says so before any of it reaches a teacher.
        if let file = env["TW_EVAL_FILE"] {
            runEvaluationProbe(file: file,
                               skillId: env["TW_EVAL_SKILL"] ?? "",
                               runs: Int(env["TW_EVAL_RUNS"] ?? "1") ?? 1)
        }

        // Framework integrity check: TW_FRAMEWORK_CHECK=1 loads the bundled
        // competency CSVs, prints what it found, and exits non-zero if
        // anything is malformed, duplicated or orphaned. Run it before a
        // release — a silently short framework is hard to notice from the UI.
        if env["TW_FRAMEWORK_CHECK"] != nil {
            do {
                let (framework, diagnostics) = try FrameworkImport.load()
                print("XQ framework \(framework.version)")
                print("levels: \(framework.levelLabels.joined(separator: " / "))")
                print(diagnostics.summary)
                // TW_FRAMEWORK_SKILL=<id> also dumps one skill, for eyeballing
                // how a progression actually reads before prompting with it.
                if let id = env["TW_FRAMEWORK_SKILL"] {
                    guard let skill = framework.skill(id: id) else {
                        print("no such skill: \(id)")
                        exit(1)
                    }
                    print("\n\(skill.id) — \(skill.competencyName) — \(skill.name)")
                    print("detail: \(skill.detail)")
                    print("example: \(skill.example)")
                    for rung in skill.progression {
                        print("  [\(rung.ordinal)] \(rung.label): \(rung.descriptor)")
                    }
                }
                print(diagnostics.isClean ? "clean" : "PROBLEMS FOUND")
                exit(diagnostics.isClean ? 0 : 1)
            } catch {
                print("FRAMEWORK ERROR: \(error.localizedDescription)")
                exit(1)
            }
        }

        // Attachment extraction test: TW_EXTRACT_FILE=<path> prints the text
        // FileAttachment pulls out of a file, or reports that it found none.
        // Exits non-zero on nil so a script can assert a format is readable.
        if let file = env["TW_EXTRACT_FILE"] {
            let url = URL(fileURLWithPath: file)
            guard let text = FileAttachment.extractText(from: url) else {
                print("EXTRACT: no readable text in \(url.lastPathComponent)")
                exit(1)
            }
            print("EXTRACT \(url.lastPathComponent) — \(text.count) chars")
            print(text)
            exit(0)
        }

        // De-identification probes. These gate the frontier-review feature and
        // are deliberately the first thing in that whole subsystem to exist:
        // nothing that can open a socket ships until the thing that stops bytes
        // is proven. TW_REDACT_TEST="<text>" redacts one string;
        // TW_REDACT_ADVERSARIAL=1 runs the regression corpus and exits non-zero
        // on any leak.
        if env["TW_REDACT_ADVERSARIAL"] != nil {
            RedactionProbe.runAdversarial()
        }
        if let text = env["TW_REDACT_TEST"] {
            RedactionProbe.runSingle(text)
        }
        // TW_REVIEW_PAYLOAD=<artifact id> prints the exact bytes a frontier
        // review would send, with no network stack involved.
        if let id = env["TW_REVIEW_PAYLOAD"] {
            MainActor.assumeIsolated { RedactionProbe.runPayload(artifactId: id) }
        }
        // The rest of the frontier-review probes: TW_REVIEW_ERRORS=1 prints
        // every failure message, TW_REVIEW_PARSE=<file> decodes a canned API
        // response, TW_REVIEW_BODY=<artifact id> prints the request body
        // without sending, TW_REVIEW_LIVE=<artifact id> actually sends (needs
        // TW_CLAUDE_KEY), and TW_AUDIT_DUMP=1 prints the audit log.
        // TW_KEYCHAIN_TEST=1 stores, reads back and deletes a throwaway secret
        // — the same calls the setup sheet makes, without the clicking.
        if env["TW_KEYCHAIN_TEST"] != nil { FrontierProbe.runKeychainTest() }
        if env["TW_REVIEW_ERRORS"] != nil { FrontierProbe.runErrors() }
        if let file = env["TW_REVIEW_PARSE"] { FrontierProbe.runParse(file: file) }
        if let id = env["TW_REVIEW_BODY"] {
            MainActor.assumeIsolated { FrontierProbe.runBody(artifactId: id) }
        }
        if let id = env["TW_REVIEW_LIVE"] {
            MainActor.assumeIsolated { FrontierProbe.runLive(artifactId: id) }
        }
        if env["TW_AUDIT_DUMP"] != nil { FrontierProbe.runAuditDump() }

        // Roster parser test: TW_ROSTER_FILE=<path> prints parsed students.
        if let file = env["TW_ROSTER_FILE"], let raw = try? String(contentsOfFile: file, encoding: .utf8) {
            for s in RosterImport.parse(raw) {
                print("\(s.name)|\(s.notes)")
            }
            exit(0)
        }

        // Export test: TW_EXPORT_PDF=<path> renders the first rubric to a PDF.
        if let path = env["TW_EXPORT_PDF"] {
            MainActor.assumeIsolated {
                let s = AppState()
                if let r = s.allRubrics.first {
                    ArtifactExport.writePDF(for: ArtifactRef(type: .rubric, id: r.id), state: s,
                                            to: URL(fileURLWithPath: path))
                    print(ArtifactExport.markdown(rubric: r).prefix(200))
                }
            }
            exit(0)
        }

        // Provenance-on-paper test: TW_EXPORT_REVIEW_PDF=<path> renders an
        // artifact that *has* a second opinion, so the printed review section
        // and the footer that says the text was sent are verifiable without
        // clicking through the app.
        if let path = env["TW_EXPORT_REVIEW_PDF"] {
            MainActor.assumeIsolated {
                let s = AppState()
                let ref = ArtifactRef(type: .activity, id: "a1")
                s.store(review: Self.sampleReview(ref: ref, state: s))
                ArtifactExport.writePDF(for: ref, state: s, to: URL(fileURLWithPath: path))
                guard let md = ArtifactExport.markdown(for: ref, state: s,
                                                       includeReview: true) else {
                    print("EXPORT: nothing rendered")
                    exit(1)
                }
                print(md)
                // The footer is the claim; if it isn't on the page, a teacher
                // could print a reviewed plan that doesn't say it was reviewed.
                guard md.contains("Reviewed off-device") else {
                    print("EXPORT: provenance line missing from markdown")
                    exit(1)
                }
            }
            exit(0)
        }

        // Skill Check export test: TW_EXPORT_EVAL_PDF=<path> renders a canned
        // evaluation to PDF and prints the Markdown form, so both exports can
        // be checked without clicking through the screen.
        if let path = env["TW_EXPORT_EVAL_PDF"] {
            guard let (framework, _) = try? FrameworkImport.load(),
                  let skill = framework.componentSkills.first(where: { $0.id == "FK.AC.2.c" }) else {
                print("EXPORT: framework unavailable")
                exit(1)
            }
            let sample = SkillEvaluation(
                id: "eval-export", createdAt: Date(timeIntervalSince1970: 0),
                workLabel: "Mural response", workSnippet: "The mural on 14th Street…",
                workCharacterCount: 1388, sourceName: "essay.txt",
                skillId: skill.id, competencyId: skill.competencyId,
                skillName: skill.name, competencyName: skill.competencyName,
                frameworkVersion: framework.version,
                levelOrdinal: 4, levelLabel: framework.levelLabel(4),
                levelDescriptor: skill.rung(4)?.descriptor ?? "",
                evidence: ["The mural kept the strike visible after the newspapers stopped covering it."],
                nextStep: "To move toward the next level, connect the mural to a second work.",
                hasMixedEvidence: false, isOffTopic: false, teacherLevel: nil)
            MainActor.assumeIsolated {
                ArtifactExport.writePDF(
                    view: PrintableEvaluationView(evaluation: sample, framework: framework),
                    to: URL(fileURLWithPath: path))
            }
            print(ArtifactExport.markdown(evaluation: sample, framework: framework))
            exit(0)
        }

        // Folder test: TW_FOLDER_TEST=1 exercises create/move/rename/delete and
        // checks the folders survive a save + reload of the JSON store.
        if env["TW_FOLDER_TEST"] != nil {
            MainActor.assumeIsolated {
                let s = AppState()
                let chatId = s.sidebarChats.first?.id ?? "c1"
                let a = s.addFolder(name: "Unit planning")
                let b = s.addFolder(name: "Temp")
                s.moveChat(chatId, toFolder: a)
                print("after move: folder A holds \(s.chats(inFolder: a).map(\.title))")
                print("moved, not copied — still unfiled? \(s.unfiledChats.contains { $0.id == chatId })")
                s.renameFolder(a, to: "Unit planning · Q1")
                s.moveChat(chatId, toFolder: b)
                print("after re-move: A=\(s.chats(inFolder: a).count) B=\(s.chats(inFolder: b).count)")
                s.deleteFolder(b)
                print("after delete B: folders=\(s.folders.map(\.name)) chat filed=\(s.chatFolder[chatId] != nil)")
                print("back in All chats after folder delete: \(s.unfiledChats.contains { $0.id == chatId })")
                s.moveChat(chatId, toFolder: a)
                s.archiveChat(chatId)
                print("archived — in folder list? \(s.chats(inFolder: a).count > 0), in All chats? \(s.unfiledChats.contains { $0.id == chatId }), in Archived? \(s.archivedChatList.contains { $0.id == chatId })")
                s.persistNow()
                let reloaded = AppState()
                print("reloaded folders: \(reloaded.folders.map(\.name))")
                print("reloaded archived: \(reloaded.archivedChatList.map(\.title))")
                reloaded.unarchiveChat(chatId)
                print("unarchived back into its folder: \(reloaded.chats(inFolder: a).map(\.title))")
            }
            exit(0)
        }

        // Mention test: TW_MENTION_TEST="<composer text>" prints the resolved
        // @mentions and the hidden context block they expand into.
        if let text = env["TW_MENTION_TEST"] {
            MainActor.assumeIsolated {
                let s = AppState()
                for m in MentionScanner.matches(in: text, catalog: s.mentionCatalog) {
                    print("match: \(m.mention.kind.rawValue) \"\(m.mention.name)\" at \(m.range.location)+\(m.range.length)")
                }
                print("--- context ---")
                print(s.mentionContext(for: text) ?? "(none)")
            }
            exit(0)
        }

        // Dictation probe: TW_DICTATE_FILE=<audio> transcribes a file with the
        // same on-device recognizer the mic button uses, and prints the text.
        if let path = env["TW_DICTATE_FILE"] {
            let semaphore = DispatchSemaphore(value: 0)
            Task.detached {
                do {
                    let text = try await DictationController.transcribeFile(at: URL(fileURLWithPath: path))
                    print("transcript: \(text)")
                } catch {
                    print("DICTATE ERROR: \(error.localizedDescription)")
                }
                semaphore.signal()
            }
            semaphore.wait()
            exit(0)
        }

        // Headless generation probe: TW_PROBE="<prompt>" streams a reply to
        // stdout and exits. Used for automated smoke tests of the model.
        if let prompt = env["TW_PROBE"] {
            let turns = [
                ChatTurn(role: .system, content: AppState().systemPrompt(chatContext: nil)),
                ChatTurn(role: .user, content: prompt),
            ]
            let semaphore = DispatchSemaphore(value: 0)
            Task.detached {
                do {
                    for try await piece in LlamaBackend.shared.streamReply(turns: turns) {
                        print(piece, terminator: "")
                        // synchronizeFile() throws an ObjC exception — and so
                        // kills the process — whenever stdout is a pipe rather
                        // than a tty, which is every scripted run.
                        fflush(stdout)
                    }
                    print("")
                } catch {
                    print("PROBE ERROR: \(error.localizedDescription)")
                }
                semaphore.signal()
            }
            semaphore.wait()
            LlamaBackend.shared.shutdown()
            exit(0)
        }

        // Model-delete probe: TW_MODEL_DELETE_TEST=1 (with TW_MODEL_ID and
        // TW_MODEL_DIR) runs the real delete path and reports what's left and
        // which model took over — deleting gigabytes deserves a regression test.
        if env["TW_MODEL_DELETE_TEST"] != nil {
            MainActor.assumeIsolated {
                let spec = env["TW_MODEL_ID"].flatMap(ModelCatalog.spec(id:)) ?? ModelCatalog.activeSpec
                print("before: \(ModelCatalog.installedSpecs.map(\.id).joined(separator: ", "))")
                print("removable: \(ModelCatalog.isRemovable(spec))")
                AppState().deleteModel(spec)
                print("after: \(ModelCatalog.installedSpecs.map(\.id).joined(separator: ", "))")
                print("active: \(ModelCatalog.activeSpec.id)")
                print("needsSetup: \(!LlamaBackend.anyModelPresent())")
            }
            exit(0)
        }

        // Model-switch probe: TW_MODEL_SWITCH_TEST=1 answers the same prompt
        // from every installed model in turn, so the reload path — freeing a
        // live Metal context and mapping a different GGUF — is exercised
        // without a GUI. Needs two models installed to prove anything.
        if env["TW_MODEL_SWITCH_TEST"] != nil {
            let specs = ModelCatalog.installedSpecs
            print("installed: \(specs.map(\.id).joined(separator: ", "))")
            guard specs.count > 1 else {
                print("SWITCH TEST SKIPPED: needs two installed models")
                exit(2)
            }
            // The selection is a real preference — put it back before exiting
            // (which skips any defer) so a probe run doesn't quietly change
            // which model the app answers with.
            let previousSelection = ModelCatalog.selectedID
            for spec in specs {
                ModelCatalog.selectedID = spec.id
                LlamaBackend.shared.unload()
                print("model: \(spec.id) → \(ModelCatalog.installedPath(for: spec) ?? "nil")")
                let turns = [ChatTurn(role: .user, content: "Reply with one short sentence about photosynthesis.")]
                let semaphore = DispatchSemaphore(value: 0)
                Task.detached {
                    do {
                        let reply = try await LlamaBackend.shared.complete(
                            turns: turns, options: GenerationOptions(temperature: 0, seed: 1, maxTokens: 24))
                        print("reply: \(reply.trimmingCharacters(in: .whitespacesAndNewlines))")
                    } catch {
                        print("SWITCH TEST ERROR: \(error.localizedDescription)")
                    }
                    fflush(stdout)
                    semaphore.signal()
                }
                semaphore.wait()
            }
            ModelCatalog.selectedID = previousSelection
            LlamaBackend.shared.shutdown()
            print("shutdown: clean")
            exit(0)
        }

        guard env["TW_SNAPSHOT"] != nil else { return }
        MainActor.assumeIsolated {
            let snapState = AppState()
            if env["TW_THEME"] == "light" { snapState.themeName = "light" }
            switch env["TW_VIEW"] {
            case "rubrics": snapState.setView(.rubrics)
            case "activities": snapState.setView(.activities)
            case "pogs": snapState.setView(.pogs)
            case "integrations": snapState.setView(.integrations)
            case "classroom": snapState.setView(.classroom)
            case "skillcheck": snapState.setView(.skillCheck)
            case "models": snapState.setView(.models)
            case "welcome": snapState.newChat()
            case "onboarding": snapState.onboardingOpen = true
            default: break
            }
            switch env["TW_PREVIEW"] {
            case "rubric": snapState.openPreview(ArtifactRef(type: .rubric, id: "r1"))
            case "activity": snapState.openPreview(ArtifactRef(type: .activity, id: "a1"))
            case "pog": snapState.openPreview(ArtifactRef(type: .pog, id: "p2"))
            case "tabs":
                snapState.openPreview(ArtifactRef(type: .activity, id: "a1"))
                snapState.openPreview(ArtifactRef(type: .rubric, id: "r1"))
            case "empty": snapState.previewOpen = true
            default: break
            }
            // TW_AUTOSEND: type a message and send it through the real
            // model, so the snapshot verifies the live chat path.
            // TW_ATTACH=<path> attaches a file to that message first.
            if let autosend = env["TW_AUTOSEND"] {
                if let attach = env["TW_ATTACH"] {
                    snapState.attachFile(at: URL(fileURLWithPath: attach))
                }
                snapState.draft = autosend
                snapState.send()
            }
            // TW_DRAFT fills the composer without sending — used to snapshot
            // how @mentions are tinted in the field.
            if let draft = env["TW_DRAFT"] { snapState.draft = draft }
            // TW_REVIEW=nokey|sheet|settings|result snapshots the second-
            // opinion surfaces. `result` seeds a finished review so the card
            // renders without a key or a network call — the payload it shows
            // is a real de-identified one from the demo classroom.
            switch env["TW_REVIEW"] {
            case "on":
                // Configured but idle — for checking that the promise copy
                // flips to the conditional wording and the panel button appears.
                snapState.frontierEnabled = true
            case "nokey":
                snapState.frontierSheet = .needsKey(ArtifactRef(type: .activity, id: "a1"))
            case "sheet":
                snapState.frontierEnabled = true
                snapState.startReview(of: ArtifactRef(type: .activity, id: "a1"))
            case "settings":
                snapState.frontierEnabled = true
                snapState.frontierSheet = .settings
            case "result":
                let ref = ArtifactRef(type: .activity, id: "a1")
                snapState.frontierEnabled = true
                snapState.store(review: Self.sampleReview(ref: ref, state: snapState))
                snapState.openPreview(ref)
            default: break
            }
            // TW_SETTINGS=1 opens the settings popover above the footer.
            if env["TW_SETTINGS"] != nil { snapState.settingsOpen = true }
            // TW_MODEL_PICKER=1 opens the model picker under the composer.
            if env["TW_MODEL_PICKER"] != nil { snapState.modelPickerOpen = true }
            _snapshotState = snapState
        }
    }

    var body: some Scene {
        WindowGroup {
            let activeState = _snapshotState ?? state
            ContentView()
                .environmentObject(activeState)
                .frame(minWidth: 1100, minHeight: 640)
                .preferredColorScheme(activeState.theme.isDark ? .dark : .light)
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 1440, height: 900)
        .commands {
            CommandGroup(after: .appInfo) {
                Button("Check for Updates…") { UpdateChecker.shared.checkForUpdates() }
                    .disabled(!UpdateChecker.shared.isAvailable)
            }
            CommandGroup(after: .textEditing) {
                Button("Search Workspace") { state.toggleSearch() }
                    .keyboardShortcut("k", modifiers: .command)
                Button("New Chat") { state.newChat() }
                    .keyboardShortcut("n", modifiers: .command)
                Button("Toggle Preview Panel") { state.togglePreview() }
                    .keyboardShortcut("p", modifiers: [.command, .shift])
            }
            CommandGroup(replacing: .help) {
                Button("\(AppInfo.productName) Tour") { state.showOnboarding() }
            }
            CommandMenu("Classroom") {
                Button("Open My Classroom") { state.setView(.classroom) }
                    .keyboardShortcut(",", modifiers: [.command, .shift])
                Divider()
                Button("Restore Previous Classroom") { state.restorePreviousClassroom() }
                    .disabled(state.classroomBackup == nil)
                Button("Restore Demo Data") { state.restoreDemoClassroom() }
            }
        }
    }

    /// A finished review for `TW_REVIEW=result`. The `payloadSent` field is a
    /// real de-identified payload built from the demo classroom, so the
    /// snapshot exercises the receipt disclosure rather than faking it.
    @MainActor
    private static func sampleReview(ref: ArtifactRef, state: AppState) -> FrontierReview {
        let lexicon = PIILexicon.build(from: state.classroom)
        let payload = (ArtifactExport.markdown(for: ref, state: state)).flatMap { markdown in
            try? ReviewPayload(ref: ref, title: state.artifact(for: ref)?.title ?? "",
                               markdown: markdown, lexicon: lexicon)
        }
        return FrontierReview(
            id: "review-sample", createdAt: Date(),
            subjectRef: ref, subjectTitle: state.artifact(for: ref)?.title ?? "Lesson plan",
            providerId: "anthropic", modelId: "claude-opus-5",
            modelDisplayName: "Claude Opus 5",
            strengths: [
                "The tiering is driven by exit-ticket data rather than a hunch.",
                "Four product options give genuine choice without four preps.",
                "The gallery close makes student thinking visible to the room.",
            ],
            suggestions: [
                ReviewSuggestion(
                    title: "The close tells you who presented, not who understood",
                    detail: "A gallery share surfaces the confident students. Add a "
                        + "three-question exit ticket in the last five minutes so you "
                        + "leave with data on everyone.", stepNumber: 4),
                ReviewSuggestion(
                    title: "Thirty minutes is tight for a product",
                    detail: "Steps 1 and 2 will eat closer to twelve minutes than five "
                        + "once transitions are counted.", stepNumber: 3),
                ReviewSuggestion(
                    title: "No landing spot for early finishers",
                    detail: "A student who finishes at minute eighteen has nowhere to go. "
                        + "Name one extension task per option.", stepNumber: nil),
            ],
            questions: [
                "What does a student who missed the last two lessons do at step 2?",
                "Do the three tiers assess the same understanding, or different depths of it?",
            ],
            payloadSent: payload?.outgoingText ?? "",
            requestBytes: payload?.byteCount ?? 0,
            auditEntryId: "audit-sample",
            studentIdOrder: lexicon.studentIdOrder)
    }

    /// Runs the placement stages headlessly and never returns — the caller is
    /// a probe branch that exits.
    private func runEvaluationProbe(file: String, skillId: String, runs: Int) -> Never {
        func fail(_ message: String) -> Never {
            print("EVAL ERROR: \(message)")
            fflush(stdout)
            exit(1)
        }

        let url = URL(fileURLWithPath: file)
        guard let raw = FileAttachment.extractText(from: url) else {
            fail("no readable text in \(url.lastPathComponent)")
        }
        let work: WorkDocument
        do {
            work = try WorkDocument(text: raw, sourceName: url.lastPathComponent)
        } catch {
            fail(error.localizedDescription)
        }

        let framework: XQFramework
        do {
            (framework, _) = try FrameworkImport.load()
        } catch {
            fail(error.localizedDescription)
        }
        guard let skill = framework.skill(id: skillId) else {
            fail("unknown skill id \(skillId.isEmpty ? "(none given — set TW_EVAL_SKILL)" : skillId)")
        }

        print("work: \(url.lastPathComponent) — \(work.sentences.count) sentences, \(work.text.count) chars")
        print("skill: \(skill.id) — \(skill.competencyName) — \(skill.name)")
        print("runs: \(runs)\n")
        EvaluationPipeline.traceRawReplies =
            ProcessInfo.processInfo.environment["TW_EVAL_VERBOSE"] != nil
        fflush(stdout)

        var levels: [Int] = []
        let semaphore = DispatchSemaphore(value: 0)
        Task.detached {
            for run in 1...max(1, runs) {
                let started = Date()
                do {
                    let placement = try await EvaluationPipeline.evaluate(
                        work: work, skill: skill, backend: LlamaBackend.shared)
                    levels.append(placement.level)
                    let rungs = placement.verdicts
                        .sorted { $0.ordinal < $1.ordinal }
                        .map { v in
                            let mark = v.meets.map { $0 ? "Y" : "N" } ?? "?"
                            return "L\(v.ordinal):\(mark)@\(v.evidenceSentence.map(String.init) ?? "-")"
                        }
                        .joined(separator: " ")
                    let elapsed = String(format: "%.1fs", Date().timeIntervalSince(started))
                    print("run \(run): level \(placement.level) "
                          + "[\(rungs)]\(placement.hasMixedEvidence ? " MIXED" : "")"
                          + "\(placement.isOffTopic ? " OFF-TOPIC" : "") \(elapsed)")
                    if let next = placement.nextStep { print("        next: \(next)") }
                } catch {
                    print("run \(run): FAILED — \(error.localizedDescription)")
                }
                fflush(stdout)
            }
            semaphore.signal()
        }
        semaphore.wait()

        let distinct = Set(levels)
        print("\nlevels: \(levels.map(String.init).joined(separator: ", "))")
        if distinct.count <= 1 {
            print("STABLE across \(levels.count) run(s)")
        } else {
            print("UNSTABLE — \(distinct.count) different levels across \(levels.count) runs")
        }
        fflush(stdout)
        LlamaBackend.shared.shutdown()
        exit(distinct.count <= 1 ? 0 : 1)
    }

}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Running from a bare executable (swift run) needs an explicit
        // activation policy for the window to come to the front.
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)

        let env = ProcessInfo.processInfo.environment

        // Live-microphone probe: TW_MIC_TEST=<seconds> runs the real dictation
        // path off the actual mic and reports every phase change, so failures
        // that only happen with live audio are visible without a GUI session.
        if let secs = env["TW_MIC_TEST"] {
            runMicTest(seconds: Double(secs) ?? 6)
            return
        }

        // Model-download probe: TW_MODEL_DL_TEST=1 (with TW_MODEL_URL,
        // TW_MODEL_SHA256, TW_MODEL_DIR) runs the first-launch download flow
        // headlessly and reports each phase change. Needs the run loop, so it
        // lives here rather than with the init-time probes.
        if env["TW_MODEL_DL_TEST"] != nil {
            runModelDownloadTest()
            return
        }

        if let path = env["TW_SNAPSHOT"] {
            // Autosend runs the real model — give it time to finish streaming.
            let delay: TimeInterval = env["TW_AUTOSEND"] != nil ? 20 : 1.5
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                // TW_AFTER=library: before capturing, jump to the library tab
                // of the artifact created by the autosent message and open it.
                if env["TW_AFTER"] == "library", let s = _snapshotState {
                    if let r = s.userRubrics.first {
                        s.setView(.rubrics); s.openPreview(ArtifactRef(type: .rubric, id: r.id))
                    } else if let a = s.userActivities.first {
                        s.setView(.activities); s.openPreview(ArtifactRef(type: .activity, id: a.id))
                    } else if let p = s.userPogs.first {
                        s.setView(.pogs); s.openPreview(ArtifactRef(type: .pog, id: p.id))
                    } else if let q = s.userQuizzes.first {
                        s.setView(.quizzes); s.openPreview(ArtifactRef(type: .quiz, id: q.id))
                    } else if let e = s.userEmails.first {
                        s.openPreview(ArtifactRef(type: .email, id: e.id))
                    }
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                    Self.captureWindow(to: path)
                    LlamaBackend.shared.shutdown()
                    exit(0)
                }
            }
        }
    }

    @MainActor private func runModelDownloadTest() {
        // TW_MODEL_ID picks which catalog model to pull; the default one is
        // what first-launch downloads, so that's the default here too.
        let spec = ProcessInfo.processInfo.environment["TW_MODEL_ID"]
            .flatMap(ModelCatalog.spec(id:)) ?? ModelCatalog.defaultSpec
        let dl = ModelDownloader.downloader(for: spec)
        print("model: \(spec.id)")
        print("source: \(dl.sourceURL)")
        // A model whose asset isn't published can't be fetched — say so rather
        // than sitting on a phase that will never change.
        guard spec.canDownload else {
            print("phase: unavailable — no published asset for \(spec.id) yet")
            exit(2)
        }
        dl.start()
        var lastPhase: ModelDownloader.Phase?
        Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { timer in
            MainActor.assumeIsolated {
                guard dl.phase != lastPhase else { return }
                lastPhase = dl.phase
                switch dl.phase {
                case .downloading(let r, let t): print("phase: downloading \(r)/\(t)")
                case .installed:
                    print("phase: installed")
                    print("locate: \(LlamaBackend.locateModelFile() ?? "nil")")
                    timer.invalidate()
                    exit(0)
                case .failed(let msg):
                    print("phase: failed — \(msg)")
                    timer.invalidate()
                    exit(1)
                default: print("phase: \(dl.phase)")
                }
            }
        }
    }

    @MainActor private func runMicTest(seconds: Double) {
        let controller = DictationController()
        _micTestController = controller
        controller.onText = { print("text: \($0)"); fflush(stdout) }
        print("launchedAsApp: \(DictationController.isLaunchedAsApp)")
        controller.start(currentText: "")

        var lastPhase: DictationController.Phase?
        let deadline = Date().addingTimeInterval(seconds)
        Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { timer in
            MainActor.assumeIsolated {
                if controller.phase != lastPhase {
                    lastPhase = controller.phase
                    print("phase: \(controller.phase)")
                    fflush(stdout)
                }
                guard Date() >= deadline else { return }
                timer.invalidate()
                controller.stop()
                print("final phase: \(controller.phase)")
                fflush(stdout)
                exit(0)
            }
        }
    }

    /// Renders the app's own window content to a PNG — no screen-recording
    /// permission needed since it never reads other apps' pixels.
    @MainActor private static func captureWindow(to path: String) {
        guard let window = NSApp.windows.first(where: { $0.isVisible }),
              let content = window.contentView else { return }
        window.setContentSize(NSSize(width: 1440, height: 900))
        window.layoutIfNeeded()
        content.displayIfNeeded()
        guard let rep = content.bitmapImageRepForCachingDisplay(in: content.bounds) else { return }
        content.cacheDisplay(in: content.bounds, to: rep)
        if let png = rep.representation(using: .png, properties: [:]) {
            try? png.write(to: URL(fileURLWithPath: path))
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }

    func applicationWillTerminate(_ notification: Notification) {
        LlamaBackend.shared.shutdown()
    }
}
