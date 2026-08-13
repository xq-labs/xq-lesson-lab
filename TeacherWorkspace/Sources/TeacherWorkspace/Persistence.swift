import Foundation

/// An element that decodes to nil instead of throwing.
///
/// `PersistedState` already defends against one kind of forward-incompatibility
/// — every post-v1 field is Optional, so an *older* document still decodes.
/// This defends against the other direction: a *newer* document containing
/// something this build has never heard of.
///
/// The concrete case is an artifact type added later. `ArtifactType` is a
/// `String` enum, so an unknown case throws, and one throw anywhere takes the
/// whole document with it — `load()` swallows it and hands the teacher an empty
/// app. Measured, not feared: a store carrying `{"type":"projectPlan"}` made
/// this build print "nothing decoded" before this existed.
///
/// The trade is deliberate. An entry this build can't read is dropped, and if
/// the teacher then saves, it's gone for good. Losing one card beats losing
/// every chat, artifact and roster they have.
struct Failable<T: Codable>: Codable {
    var value: T?

    init(_ value: T?) { self.value = value }

    init(from decoder: Decoder) throws {
        // Never throws, so the surrounding array always decodes.
        value = try? T(from: decoder)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        if let value { try container.encode(value) } else { try container.encodeNil() }
    }
}

/// Everything the app persists across launches, as one JSON document.
struct PersistedState: Codable {
    var extraChats: [Chat] = []
    var extraMessages: [String: [Message]] = [:]
    var userRubrics: [Rubric] = []
    var userActivities: [Activity] = []
    var userPogs: [Pog] = []
    var userQuizzes: [Quiz] = []
    var userEmails: [EmailDraft] = []
    var pogLevels: [String: Int] = [:]
    var themeName: String = "dark"
    var connections: [String: Bool] = [:]
    var classroom: Classroom = .demo
    var contextByChat: [String: String] = [:]
    var classroomBackup: Classroom?
    var previewWidth: Double?
    /// Optional so stores written before this field existed still decode.
    var chatTitleOverrides: [String: String]?
    /// Teacher-made sidebar folders, and which folder each chat sits in.
    var folders: [Folder]?
    var chatFolder: [String: String]?
    var archivedChats: [String]?
    var sidebarWidth: Double?
    /// True once the welcome tour has been seen (or skipped).
    var hasSeenOnboarding: Bool?
    /// Saved Skill Check results, and the component skills used most recently.
    /// Optional like everything else added after v1 — `load()` swallows any
    /// decode error and returns nil, and a synthesized decoder throws on a
    /// missing key even when the property has a default, so a non-optional
    /// field here would wipe every existing teacher's chats and classroom on
    /// the first launch of the new build.
    var skillEvaluations: [SkillEvaluation]?
    var recentSkillIds: [String]?
    /// Saved second opinions, and whether the consent explainer has been read
    /// once. Optional for the reason spelled out above — and the API key that
    /// makes them possible is deliberately *not* here: it lives in the
    /// Keychain, and the audit trail lives in its own append-only file.
    /// Wrapped, because a review's `subjectRef` names an artifact type — so a
    /// review of something added in a later version would otherwise take the
    /// whole document down when an older build reads it.
    var frontierReviews: [Failable<FrontierReview>]?
    var hasSeenFrontierConsent: Bool?
}

/// JSON store at ~/Library/Application Support/LessonLab/store.json.
/// Disabled during headless test runs (TW_SNAPSHOT / TW_PROBE / TW_PARSE_FILE)
/// so they never touch the user's real data; TW_STORE=<path> re-enables
/// persistence against an explicit file for automated persistence tests.
enum PersistenceStore {
    static var fileURL: URL? {
        let env = ProcessInfo.processInfo.environment
        if let override = env["TW_STORE"] {
            return URL(fileURLWithPath: override)
        }
        // Every headless probe belongs in this list — a probe that builds an
        // AppState would otherwise autosave over the teacher's real store.
        for probe in ["TW_SNAPSHOT", "TW_PROBE", "TW_PARSE_FILE", "TW_EVAL_FILE",
                      "TW_EXTRACT_FILE", "TW_FRAMEWORK_CHECK",
                      "TW_MODEL_DELETE_TEST", "TW_REDACT_TEST",
                      "TW_REDACT_ADVERSARIAL", "TW_REVIEW_PAYLOAD", "TW_REVIEW_ERRORS",
                      "TW_REVIEW_PARSE", "TW_REVIEW_BODY", "TW_REVIEW_LIVE",
                      "TW_AUDIT_DUMP", "TW_EXPORT_REVIEW_PDF", "TW_KEYCHAIN_TEST",
                      "TW_STORE_FUTURE"] where env[probe] != nil {
            return nil
        }
        guard let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
        else { return nil }
        let dir = base.appendingPathComponent(AppInfo.supportDirectory, isDirectory: true)
        migrateLegacyStore(into: dir, from: base)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("store.json")
    }

    /// The app shipped its store under the old "TeacherWorkspace" name before
    /// the rename. Move it across once, and only when nothing is there yet, so
    /// an existing install keeps its chats, folders and classroom.
    private static func migrateLegacyStore(into dir: URL, from base: URL) {
        let fm = FileManager.default
        let legacy = base.appendingPathComponent("TeacherWorkspace", isDirectory: true)
        guard fm.fileExists(atPath: legacy.path), !fm.fileExists(atPath: dir.path) else { return }
        try? fm.moveItem(at: legacy, to: dir)
    }

    static func load() -> PersistedState? {
        guard let url = fileURL, let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(PersistedState.self, from: data)
    }

    /// TW_STORE_FUTURE=1 — asserts a store written by a *later* version still
    /// decodes here.
    ///
    /// Needs no fixture: it builds the document inline, so it keeps testing the
    /// real risk as the app grows. The failure it guards against is silent and
    /// total — one unreadable value makes `load()` return nil, and the teacher
    /// opens an empty app with every chat, artifact and roster gone.
    static func runFutureCompatibilityCheck() -> Never {
        // A document from a build that added a "projectPlan" artifact type: one
        // chat message linking to it, and one saved review about it.
        let json = """
        {
          "extraChats": [{"id": "c-future", "title": "Water quality project"}],
          "extraMessages": {"c-future": [
            {"id": "\(UUID().uuidString)", "role": "user", "text": "Plan the water quality project"},
            {"id": "\(UUID().uuidString)", "role": "assistant", "text": "Here's the plan.",
             "artifact": {"type": "projectPlan", "id": "pp-1"}}
          ]},
          "userRubrics": [], "userActivities": [], "userPogs": [],
          "userQuizzes": [], "userEmails": [], "pogLevels": {},
          "themeName": "dark", "connections": {},
          "classroom": {"teacherName": "Dana Alvarez", "school": "Crestview High",
                        "subject": "Science", "classes": [], "isDemo": false},
          "contextByChat": {},
          "frontierReviews": [
            {"id": "review-future", "createdAt": 776000000,
             "subjectRef": {"type": "projectPlan", "id": "pp-1"},
             "subjectTitle": "Water Quality Project", "providerId": "anthropic",
             "modelId": "claude-opus-5", "modelDisplayName": "Claude Opus 5",
             "strengths": [], "suggestions": [], "questions": [],
             "payloadSent": "", "requestBytes": 0, "auditEntryId": "a",
             "studentIdOrder": []}
          ],
          "somethingAddedLater": {"a": 1}
        }
        """

        print("Forward compatibility — a store from a newer build\n"
              + String(repeating: "─", count: 78))
        guard let saved = try? JSONDecoder().decode(PersistedState.self,
                                                    from: Data(json.utf8)) else {
            print("✘ nothing decoded — a teacher downgrading would lose everything")
            print("\nSomething persisted stopped tolerating values it doesn't know.")
            print("See `Failable` and `Message.init(from:)` in Persistence/Models.")
            exit(1)
        }

        var failed = false
        func check(_ name: String, _ ok: Bool) {
            print("  \(ok ? "✓" : "✘") \(name)")
            if !ok { failed = true }
        }
        check("the document survives", true)
        check("chat kept", saved.extraChats.count == 1)
        check("both messages kept", saved.extraMessages["c-future"]?.count == 2)
        check("the message's text survives",
              saved.extraMessages["c-future"]?.last?.text == "Here's the plan.")
        check("only the unreadable card reference is dropped",
              saved.extraMessages["c-future"]?.last?.artifact == nil)
        check("unreadable review dropped, not fatal",
              (saved.frontierReviews?.compactMap(\.value).count ?? -1) == 0)
        check("classroom intact", saved.classroom.teacherName == "Dana Alvarez")

        print(String(repeating: "─", count: 78))
        print(failed ? "FAILED" : "A newer store degrades instead of destroying.")
        exit(failed ? 1 : 0)
    }

    static func save(_ state: PersistedState) {
        guard let url = fileURL else { return }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(state) else { return }
        try? data.write(to: url, options: .atomic)
    }
}
