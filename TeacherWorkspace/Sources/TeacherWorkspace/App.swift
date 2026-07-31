import SwiftUI

@MainActor private var _snapshotState: AppState?
@MainActor private var _micTestController: DictationController?

@main
struct LessonLabApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var state = AppState()

    init() {
        // Snapshot mode for automated UI verification:
        // TW_SNAPSHOT=<out.png> [TW_THEME=light] [TW_SETTINGS=1] [TW_VIEW=rubrics|activities|pogs|integrations|welcome|onboarding] [TW_PREVIEW=rubric|activity|pog]
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
                        FileHandle.standardOutput.synchronizeFile()
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
            // TW_SETTINGS=1 opens the settings popover above the footer.
            if env["TW_SETTINGS"] != nil { snapState.settingsOpen = true }
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
        let dl = ModelDownloader.shared
        print("source: \(ModelDownloader.sourceURL)")
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
