import Foundation

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
    var installedSkills: [String: Bool]?
    /// Teacher-made sidebar folders, and which folder each chat sits in.
    var folders: [Folder]?
    var chatFolder: [String: String]?
    var archivedChats: [String]?
    var sidebarWidth: Double?
    /// True once the welcome tour has been seen (or skipped).
    var hasSeenOnboarding: Bool?
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
        if env["TW_SNAPSHOT"] != nil || env["TW_PROBE"] != nil || env["TW_PARSE_FILE"] != nil {
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

    static func save(_ state: PersistedState) {
        guard let url = fileURL else { return }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(state) else { return }
        try? data.write(to: url, options: .atomic)
    }
}
