import SwiftUI
import Combine

enum MainView: Hashable {
    case chat, rubrics, activities, pogs, quizzes, integrations, classroom
}

@MainActor
final class AppState: ObservableObject {
    @Published var view: MainView = .chat
    @Published var activeChat: String? = "c1"
    @Published var themeName: String = "dark"
    @Published var settingsOpen = false
    /// First-run welcome tour overlay — reopenable from the header "?" button.
    @Published var onboardingOpen = false
    /// Persisted so the tour only auto-opens on the first launch.
    var hasSeenOnboarding = false
    /// Demo Google Calendar popover in the header (mock-connected plugin).
    @Published var scheduleOpen = false
    /// The mock-connected plugins (Google Calendar and its schedule) are part
    /// of the demo story. Once the teacher is on their own classroom, showing
    /// a green "Connected" dot for something that isn't wired up would be a
    /// lie — so they go away with the rest of the sample data.
    var showsDemoPlugins: Bool { classroom.isDemo }
    /// Whether the preview panel is showing (it can be open with no tabs —
    /// that's the empty state listing the chat's artifacts).
    @Published var previewOpen = false
    /// Documents open in the preview panel, in tab order.
    @Published var previewTabs: [ArtifactRef] = []
    @Published var activePreviewTab: ArtifactRef?
    /// User-resizable panel width (drag the left edge).
    @Published var previewWidth: CGFloat = 430
    /// User-resizable sidebar width (drag its right edge).
    @Published var sidebarWidth: CGFloat = 272

    /// The document currently shown in the panel.
    var preview: ArtifactRef? { activePreviewTab }
    @Published var searchOpen = false
    @Published var query = ""
    @Published var draft = ""
    @Published var extraMessages: [String: [Message]] = [:]
    @Published var extraChats: [Chat] = []
    /// Renames for the static demo chats (user chats are renamed in place).
    @Published var chatTitleOverrides: [String: String] = [:]
    @Published var pogLevels: [String: Int] = [:]
    @Published var connections: [String: Bool] = [
        "classroom": true, "calendar": true, "drive": true,
        "sis": true, "gmail": true, "seesaw": false, "canvas": false,
    ]
    /// Skills tab on the Plugins page — installed state per skill key.
    @Published var installedSkills: [String: Bool] = [
        "rubric-builder": true, "lesson-planner": true, "exit-tickets": true,
        "family-emails": true, "differentiation": false, "pog-updater": false,
    ]
    /// Bumped after sending so the chat scrolls to the newest message.
    @Published var scrollTick = 0
    /// True while the on-device model is generating a reply.
    @Published var isStreaming = false
    /// Artifacts created by the assistant in this session, newest first.
    @Published var userRubrics: [Rubric] = []
    @Published var userActivities: [Activity] = []
    @Published var userPogs: [Pog] = []
    @Published var userQuizzes: [Quiz] = []
    @Published var userEmails: [EmailDraft] = []
    /// The teacher's real setup — drives the system prompt and sidebar.
    @Published var classroom: Classroom = .demo
    /// Per-chat "Class context" pill selection (class or student name).
    @Published var contextByChat: [String: String] = [:]
    /// Context chosen on the welcome screen before the chat exists.
    @Published var pendingContext: String?
    /// The classroom that was replaced by "Start fresh" / "Restore demo" —
    /// one level of undo for destructive classroom resets.
    @Published var classroomBackup: Classroom?
    /// Files/artifacts queued in the composer for the next message.
    @Published var pendingAttachments: [PendingAttachment] = []
    /// Teacher-made sidebar folders, in display order.
    @Published var folders: [Folder] = []
    /// chat id → folder id. Chats with no entry live in All chats only.
    @Published var chatFolder: [String: String] = [:]
    /// Archived chat ids. Archiving hides a chat from Folders and All chats
    /// without touching its folder, so unarchiving puts it back where it was.
    @Published var archivedChats: Set<String> = []

    private var generationTask: Task<Void, Never>?
    private var lastScrollBump = Date.distantPast
    private var saveCancellable: AnyCancellable?
    private var terminateObserver: NSObjectProtocol?

    let backend: ChatBackend = LlamaBackend.shared
    var modelAvailable: Bool { LlamaBackend.locateModelFile() != nil }
    /// First run with no model at all: the app is unusable, so setup blocks
    /// the whole UI. Once any model exists, downloads never block again.
    var needsModelSetup: Bool { !modelAvailable && !LlamaBackend.anyModelPresent() }

    var theme: Theme { themeName == "light" ? .light : .dark }

    init() {
        if let saved = PersistenceStore.load() {
            extraChats = saved.extraChats
            extraMessages = saved.extraMessages
            userRubrics = saved.userRubrics
            userActivities = saved.userActivities
            userPogs = saved.userPogs
            userQuizzes = saved.userQuizzes
            userEmails = saved.userEmails
            pogLevels = saved.pogLevels
            themeName = saved.themeName
            connections = connections.merging(saved.connections) { _, new in new }
            installedSkills = installedSkills.merging(saved.installedSkills ?? [:]) { _, new in new }
            chatTitleOverrides = saved.chatTitleOverrides ?? [:]
            folders = saved.folders ?? []
            chatFolder = saved.chatFolder ?? [:]
            archivedChats = Set(saved.archivedChats ?? [])
            classroom = saved.classroom
            contextByChat = saved.contextByChat
            classroomBackup = saved.classroomBackup
            if let w = saved.previewWidth { previewWidth = CGFloat(w) }
            if let w = saved.sidebarWidth { sidebarWidth = CGFloat(w) }
            hasSeenOnboarding = saved.hasSeenOnboarding ?? false
            // Demo default chat only makes sense while the demo data shows.
            if !classroom.isDemo, activeChat == "c1" { activeChat = nil }
        }
        // Welcome tour on first launch (including the first launch after the
        // tour shipped). Headless test modes have no store and never see it.
        if PersistenceStore.fileURL != nil, !hasSeenOnboarding {
            onboardingOpen = true
        }
        // Debounced autosave — objectWillChange fires on every mutation; by
        // the time the debounce elapses the new state is in place.
        saveCancellable = objectWillChange
            .debounce(for: .seconds(1), scheduler: DispatchQueue.main)
            .sink { [weak self] _ in self?.persistNow() }
        // The setup card observes the downloader directly; this nudge is for
        // everything else that keys off `modelAvailable` (composer footer).
        ModelDownloader.shared.onInstalled = { [weak self] in self?.objectWillChange.send() }
        terminateObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.willTerminateNotification, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.persistNow() }
        }
    }

    func persistNow() {
        PersistenceStore.save(PersistedState(
            extraChats: extraChats,
            extraMessages: extraMessages,
            userRubrics: userRubrics,
            userActivities: userActivities,
            userPogs: userPogs,
            userQuizzes: userQuizzes,
            userEmails: userEmails,
            pogLevels: pogLevels,
            themeName: themeName,
            connections: connections,
            classroom: classroom,
            contextByChat: contextByChat,
            classroomBackup: classroomBackup,
            previewWidth: Double(previewWidth),
            chatTitleOverrides: chatTitleOverrides,
            installedSkills: installedSkills,
            folders: folders,
            chatFolder: chatFolder,
            archivedChats: Array(archivedChats).sorted(),
            sidebarWidth: Double(sidebarWidth),
            hasSeenOnboarding: hasSeenOnboarding))
    }

    // MARK: - Folders

    /// Creates a folder and returns its id so the sidebar can drop straight
    /// into renaming it.
    @discardableResult
    func addFolder(name: String = "New folder") -> String {
        let id = "folder-\(UUID().uuidString)"
        folders.append(Folder(id: id, name: name))
        return id
    }

    func renameFolder(_ id: String, to newName: String) {
        let trimmed = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let i = folders.firstIndex(where: { $0.id == id }) else { return }
        folders[i].name = trimmed
    }

    /// Deleting a folder never deletes chats — they fall back to All chats.
    func deleteFolder(_ id: String) {
        folders.removeAll { $0.id == id }
        chatFolder = chatFolder.filter { $0.value != id }
    }

    /// `nil` moves the chat out of every folder; it stays in All chats.
    func moveChat(_ chatId: String, toFolder folderId: String?) {
        if let folderId, folders.contains(where: { $0.id == folderId }) {
            chatFolder[chatId] = folderId
        } else {
            chatFolder.removeValue(forKey: chatId)
        }
    }

    func chats(inFolder folderId: String) -> [Chat] {
        sidebarChats.filter { chatFolder[$0.id] == folderId }
    }

    // MARK: - Archive

    func archiveChat(_ id: String) {
        archivedChats.insert(id)
        // Don't strand the teacher on a chat they just filed away.
        if activeChat == id { activeChat = nil }
    }

    func unarchiveChat(_ id: String) {
        archivedChats.remove(id)
    }

    func isArchived(_ id: String) -> Bool { archivedChats.contains(id) }

    /// Archived chats, newest first, whatever folder they belong to.
    var archivedChatList: [Chat] {
        everyChat.filter { archivedChats.contains($0.id) }
    }

    /// Every chat once, newest first — user chats ahead of the samples,
    /// including archived ones.
    var everyChat: [Chat] {
        var seen = Set<String>()
        return (extraChats.reversed().map(resolved) + allChats.map(\.chat))
            .filter { seen.insert($0.id).inserted }
    }

    /// The chats the sidebar's Folders and All chats sections draw from —
    /// everything except what's archived.
    var sidebarChats: [Chat] {
        everyChat.filter { !archivedChats.contains($0.id) }
    }

    /// Chats not in any folder. Filing a chat *moves* it — it leaves this list
    /// and lives under its folder instead, so it never appears twice.
    var unfiledChats: [Chat] {
        sidebarChats.filter { chatFolder[$0.id] == nil }
    }

    // MARK: - Derived data

    /// A chat with any rename override applied (demo chats are static).
    private func resolved(_ chat: Chat) -> Chat {
        guard let t = chatTitleOverrides[chat.id] else { return chat }
        return Chat(id: chat.id, title: t)
    }

    /// Double-click rename from the header. User chats are renamed in place;
    /// demo chats (static SampleData) get a persisted override.
    func renameChat(_ id: String, to newTitle: String) {
        let trimmed = newTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        if let i = extraChats.firstIndex(where: { $0.id == id }) {
            extraChats[i].title = trimmed
            chatTitleOverrides[id] = nil
        } else {
            chatTitleOverrides[id] = trimmed
        }
    }

    var sidebarGroups: [ChatGroup] {
        var groups: [ChatGroup] = []
        if !extraChats.isEmpty {
            groups.append(ChatGroup(name: "Recent", chats: extraChats))
        }
        if classroom.isDemo {
            let demo = SampleData.classGroups + SampleData.studentGroups
            groups.append(contentsOf: demo.map {
                ChatGroup(name: $0.name, chats: $0.chats.map(resolved))
            })
        } else {
            // Real classroom: show the teacher's classes (chats attach to
            // classes in a later phase — empty groups are fine).
            for cls in classroom.classes where !cls.name.isEmpty {
                groups.append(ChatGroup(name: cls.name, chats: []))
            }
        }
        return groups
    }

    /// Index of the first per-student group in sidebarGroups, for the "Students" header.
    var firstStudentGroupName: String? {
        classroom.isDemo ? SampleData.studentGroups.first?.name : nil
    }

    var allChats: [(chat: Chat, group: String)] {
        var out: [(Chat, String)] = []
        if classroom.isDemo {
            for g in SampleData.classGroups + SampleData.studentGroups {
                for c in g.chats { out.append((resolved(c), g.name)) }
            }
        }
        for c in extraChats { out.append((c, "Recent")) }
        return out
    }

    var headerTitle: String {
        switch view {
        case .chat:
            if let id = activeChat, let found = allChats.first(where: { $0.chat.id == id }) {
                return found.chat.title
            }
            return "New chat"
        case .rubrics: return "Rubrics"
        case .activities: return "Activities"
        case .pogs: return "Portraits of a Graduate"
        case .quizzes: return "Quizzes"
        case .integrations: return "Plugins"
        case .classroom: return "My Classroom"
        }
    }

    /// Time-of-day greeting for the welcome screen.
    var greeting: String {
        let hour = Calendar.current.component(.hour, from: Date())
        let salutation = hour < 12 ? "Good morning" : (hour < 17 ? "Good afternoon" : "Good evening")
        let name = classroom.firstName
        return name.isEmpty ? "\(salutation)." : "\(salutation), \(name)."
    }

    var headerChip: String? {
        guard view == .chat, let id = activeChat else { return nil }
        return SampleData.chatMeta[id] ?? "New"
    }

    var messages: [Message] {
        guard view == .chat, let id = activeChat else { return [] }
        let seeded = classroom.isDemo ? (SampleData.baseMessages[id] ?? []) : []
        return seeded + (extraMessages[id] ?? [])
    }

    var isWelcome: Bool { view == .chat && activeChat == nil }

    // User-created artifacts come first; demo samples show until the teacher
    // makes the classroom their own.
    var allRubrics: [Rubric] { userRubrics + (classroom.isDemo ? SampleData.rubrics : []) }
    var allActivities: [Activity] { userActivities + (classroom.isDemo ? SampleData.activities : []) }
    var allPogs: [Pog] { userPogs + (classroom.isDemo ? SampleData.pogs : []) }
    var allQuizzes: [Quiz] { userQuizzes }
    var allEmails: [EmailDraft] { userEmails }

    func rubric(id: String) -> Rubric? { allRubrics.first { $0.id == id } }
    func activity(id: String) -> Activity? { allActivities.first { $0.id == id } }
    func pog(id: String) -> Pog? { allPogs.first { $0.id == id } }
    func quiz(id: String) -> Quiz? { allQuizzes.first { $0.id == id } }
    func email(id: String) -> EmailDraft? { allEmails.first { $0.id == id } }

    /// User-created artifacts are editable; demo samples are not.
    func isUserArtifact(_ ref: ArtifactRef) -> Bool {
        switch ref.type {
        case .rubric: return userRubrics.contains { $0.id == ref.id }
        case .activity: return userActivities.contains { $0.id == ref.id }
        case .pog: return userPogs.contains { $0.id == ref.id }
        case .quiz: return userQuizzes.contains { $0.id == ref.id }
        case .email: return userEmails.contains { $0.id == ref.id }
        }
    }

    func deleteArtifact(_ ref: ArtifactRef) {
        switch ref.type {
        case .rubric: userRubrics.removeAll { $0.id == ref.id }
        case .activity: userActivities.removeAll { $0.id == ref.id }
        case .pog:
            userPogs.removeAll { $0.id == ref.id }
            pogLevels = pogLevels.filter { !$0.key.hasPrefix("\(ref.id)-") }
        case .quiz: userQuizzes.removeAll { $0.id == ref.id }
        case .email: userEmails.removeAll { $0.id == ref.id }
        }
        closeTab(ref)
    }

    func userRubricBinding(id: String) -> Binding<Rubric>? {
        guard userRubrics.contains(where: { $0.id == id }) else { return nil }
        return Binding(
            get: { [weak self] in self?.userRubrics.first { $0.id == id } ?? Rubric(id: id, title: "", sub: "", meta: "", criteria: []) },
            set: { [weak self] new in
                guard let self, let i = self.userRubrics.firstIndex(where: { $0.id == id }) else { return }
                self.userRubrics[i] = new
            })
    }

    func userActivityBinding(id: String) -> Binding<Activity>? {
        guard userActivities.contains(where: { $0.id == id }) else { return nil }
        return Binding(
            get: { [weak self] in self?.userActivities.first { $0.id == id } ?? Activity(id: id, title: "", meta: "", desc: "", steps: []) },
            set: { [weak self] new in
                guard let self, let i = self.userActivities.firstIndex(where: { $0.id == id }) else { return }
                self.userActivities[i] = new
            })
    }

    func userPogBinding(id: String) -> Binding<Pog>? {
        guard userPogs.contains(where: { $0.id == id }) else { return nil }
        return Binding(
            get: { [weak self] in self?.userPogs.first { $0.id == id } ?? Pog(id: id, title: "", sub: "", meta: "", comps: []) },
            set: { [weak self] new in
                guard let self, let i = self.userPogs.firstIndex(where: { $0.id == id }) else { return }
                self.userPogs[i] = new
            })
    }

    func artifact(for ref: ArtifactRef) -> (title: String, meta: String)? {
        switch ref.type {
        case .rubric:
            guard let r = rubric(id: ref.id) else { return nil }
            return (r.title, r.meta)
        case .activity:
            guard let a = activity(id: ref.id) else { return nil }
            return (a.title, a.meta)
        case .pog:
            guard let p = pog(id: ref.id) else { return nil }
            return (p.title, p.meta)
        case .quiz:
            guard let q = quiz(id: ref.id) else { return nil }
            return (q.title, q.meta)
        case .email:
            guard let e = email(id: ref.id) else { return nil }
            return (e.title, e.meta)
        }
    }

    /// Inserts a parsed artifact into its library and returns its reference.
    /// Idempotent by id (stream re-parses), and a matching title *updates*
    /// the existing user artifact in place — "make the third criterion
    /// stricter" replaces the rubric instead of duplicating it.
    @discardableResult
    func store(_ parsed: ArtifactParser.ParsedArtifact) -> ArtifactRef {
        func sameTitle(_ a: String, _ b: String) -> Bool {
            a.trimmingCharacters(in: .whitespaces).lowercased() == b.trimmingCharacters(in: .whitespaces).lowercased()
        }
        switch parsed {
        case .rubric(var r):
            if userRubrics.contains(where: { $0.id == r.id }) { return ArtifactRef(type: .rubric, id: r.id) }
            if let i = userRubrics.firstIndex(where: { sameTitle($0.title, r.title) }) {
                r.id = userRubrics[i].id
                userRubrics[i] = r
            } else {
                userRubrics.insert(r, at: 0)
            }
            return ArtifactRef(type: .rubric, id: r.id)
        case .activity(var a):
            if userActivities.contains(where: { $0.id == a.id }) { return ArtifactRef(type: .activity, id: a.id) }
            if let i = userActivities.firstIndex(where: { sameTitle($0.title, a.title) }) {
                a.id = userActivities[i].id
                userActivities[i] = a
            } else {
                userActivities.insert(a, at: 0)
            }
            return ArtifactRef(type: .activity, id: a.id)
        case .pog(var p):
            if userPogs.contains(where: { $0.id == p.id }) { return ArtifactRef(type: .pog, id: p.id) }
            if let i = userPogs.firstIndex(where: { sameTitle($0.title, p.title) }) {
                p.id = userPogs[i].id
                userPogs[i] = p
                // Fresh model levels supersede stale pip edits.
                pogLevels = pogLevels.filter { !$0.key.hasPrefix("\(p.id)-") }
            } else {
                userPogs.insert(p, at: 0)
            }
            return ArtifactRef(type: .pog, id: p.id)
        case .quiz(var q):
            if userQuizzes.contains(where: { $0.id == q.id }) { return ArtifactRef(type: .quiz, id: q.id) }
            if let i = userQuizzes.firstIndex(where: { sameTitle($0.title, q.title) }) {
                q.id = userQuizzes[i].id
                userQuizzes[i] = q
            } else {
                userQuizzes.insert(q, at: 0)
            }
            return ArtifactRef(type: .quiz, id: q.id)
        case .email(var e):
            if userEmails.contains(where: { $0.id == e.id }) { return ArtifactRef(type: .email, id: e.id) }
            if let i = userEmails.firstIndex(where: { sameTitle($0.title, e.title) }) {
                e.id = userEmails[i].id
                userEmails[i] = e
            } else {
                userEmails.insert(e, at: 0)
            }
            return ArtifactRef(type: .email, id: e.id)
        }
    }

    /// The context pill's current selection for the active (or pending) chat.
    var composerContext: String? {
        if let id = activeChat { return contextByChat[id] }
        return pendingContext
    }

    func setComposerContext(_ value: String?) {
        if let id = activeChat {
            if let value { contextByChat[id] = value } else { contextByChat.removeValue(forKey: id) }
        } else {
            pendingContext = value
        }
    }

    var canRegenerate: Bool {
        guard !isStreaming, view == .chat, let id = activeChat,
              let msgs = extraMessages[id], msgs.count >= 2,
              msgs.last?.role == .assistant, msgs[msgs.count - 2].role == .user else { return false }
        return true
    }

    /// Re-runs the last user message (removing the last exchange first).
    func regenerate() {
        guard canRegenerate, let id = activeChat, var msgs = extraMessages[id] else { return }
        let userText = msgs[msgs.count - 2].text
        msgs.removeLast(2)
        extraMessages[id] = msgs
        draft = userText
        send()
    }

    /// Empties the classroom, keeping what it replaced for undo.
    func startFreshClassroom() {
        classroomBackup = classroom
        classroom = Classroom(isDemo: false)
        activeChat = nil
    }

    /// Brings back Dana Alvarez + the sample chats and libraries. Restoring
    /// from the My Classroom banner passes `returnToChat: false` so the
    /// teacher stays on the page and sees the roster reappear.
    func restoreDemoClassroom(returnToChat: Bool = true) {
        classroomBackup = classroom
        classroom = .demo
        activeChat = nil
        // The schedule popover hides itself while the demo plugins are gone;
        // clear the flag so restoring doesn't pop it open unprompted.
        scheduleOpen = false
        if returnToChat { view = .chat }
    }

    /// Swaps the current classroom with the backup, so restoring is itself
    /// undoable.
    func restorePreviousClassroom() {
        guard let backup = classroomBackup else { return }
        let current = classroom
        classroom = backup
        classroomBackup = current
        activeChat = nil
    }

    func attachFile(at url: URL) {
        guard let attachment = FileAttachment.attachment(from: url) else { return }
        pendingAttachments.append(attachment)
    }

    /// Attaches a library artifact's content as chat context.
    func attachArtifact(_ ref: ArtifactRef) {
        guard let md = ArtifactExport.markdown(for: ref, state: self),
              let meta = artifact(for: ref) else { return }
        var text = md
        if text.count > FileAttachment.maxCharacters {
            text = String(text.prefix(FileAttachment.maxCharacters)) + "\n…[truncated]"
        }
        pendingAttachments.append(PendingAttachment(name: meta.title, text: text))
    }

    // MARK: - Actions

    /// Reopens the welcome tour (header "?" button and Help menu).
    func showOnboarding() {
        settingsOpen = false
        scheduleOpen = false
        onboardingOpen = true
    }

    func dismissOnboarding() {
        onboardingOpen = false
        hasSeenOnboarding = true
    }

    func setView(_ v: MainView) {
        view = v
        settingsOpen = false
    }

    func openChat(_ id: String) {
        cancelGeneration()
        view = .chat
        activeChat = id
        scrollTick += 1
    }

    func cancelGeneration() {
        generationTask?.cancel()
        generationTask = nil
        isStreaming = false
    }

    func newChat() {
        cancelGeneration()
        view = .chat
        activeChat = nil
        settingsOpen = false
    }

    func openPreview(_ ref: ArtifactRef) {
        previewOpen = true
        if !previewTabs.contains(ref) { previewTabs.append(ref) }
        activePreviewTab = ref
    }

    /// Closes one tab; the panel stays open (empty state when none remain).
    func closeTab(_ ref: ArtifactRef) {
        guard let idx = previewTabs.firstIndex(of: ref) else { return }
        previewTabs.remove(at: idx)
        if activePreviewTab == ref {
            activePreviewTab = previewTabs.indices.contains(idx)
                ? previewTabs[idx]
                : previewTabs.last
        }
    }

    func closePreview() {
        previewOpen = false
    }

    func togglePreview() {
        previewOpen.toggle()
    }

    /// Artifacts referenced by the active chat's messages, in order — the
    /// preview panel's empty state.
    var activeChatArtifacts: [ArtifactRef] {
        guard let id = activeChat else { return [] }
        let seeded = classroom.isDemo ? (SampleData.baseMessages[id] ?? []) : []
        var seen = Set<String>()
        var out: [ArtifactRef] = []
        for msg in seeded + (extraMessages[id] ?? []) {
            if let ref = msg.artifact, artifact(for: ref) != nil, seen.insert(ref.id).inserted {
                out.append(ref)
            }
        }
        return out
    }

    func toggleSearch() {
        searchOpen.toggle()
        query = ""
    }

    func send() {
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty || !pendingAttachments.isEmpty, !isStreaming else { return }
        var chatId = activeChat
        if chatId == nil {
            let id = "new-\(UUID().uuidString)"
            let titleSource = text.isEmpty ? (pendingAttachments.first?.name ?? "New chat") : text
            let title = titleSource.count > 42 ? String(titleSource.prefix(42)) + "…" : titleSource
            extraChats.append(Chat(id: id, title: title))
            chatId = id
        }
        guard let id = chatId else { return }
        if let pending = pendingContext {
            contextByChat[id] = pending
            pendingContext = nil
        }
        var userMessage = Message(role: .user, text: text)
        var hidden: [String] = []
        if !pendingAttachments.isEmpty {
            userMessage.attachmentNames = pendingAttachments.map(\.name)
            hidden.append(pendingAttachments
                .map { "[Attached: \($0.name)]\n\($0.text)" }
                .joined(separator: "\n\n"))
            pendingAttachments = []
        }
        // @mentions expand into the roster note / rubric / activity behind the
        // name, so the model works from the real thing rather than a label.
        if let referenced = mentionContext(for: text) { hidden.append(referenced) }
        if !hidden.isEmpty { userMessage.hiddenContext = hidden.joined(separator: "\n\n") }
        extraMessages[id, default: []].append(userMessage)
        draft = ""
        activeChat = id
        view = .chat
        scrollTick += 1

        let turns = buildTurns(chatId: id)
        // Empty assistant message that the stream fills in.
        extraMessages[id, default: []].append(Message(role: .assistant, text: ""))
        isStreaming = true

        // Deterministic per-send prefix so re-parsing the stream stores each
        // artifact once (idempotent by id).
        let artifactIdPrefix = "chatart-\(Int(Date().timeIntervalSince1970 * 1000))"

        generationTask = Task { [weak self] in
            guard let self else { return }
            var raw = ""
            do {
                for try await piece in self.backend.streamReply(turns: turns) {
                    if Task.isCancelled { break }
                    raw += piece
                    self.applyStreamUpdate(chatId: id, raw: raw, idPrefix: artifactIdPrefix)
                }
            } catch {
                raw += "\n⚠️ \(error.localizedDescription)"
            }
            self.applyStreamUpdate(chatId: id, raw: raw, idPrefix: artifactIdPrefix, final: true)
            if self.activeChat == id { self.isStreaming = false }
            self.generationTask = nil
            self.scrollTick += 1
        }
    }

    /// Re-parses the accumulated reply, hides artifact JSON from the bubble,
    /// stores completed artifacts in their libraries, and links the first one
    /// to the message as a clickable card.
    private func applyStreamUpdate(chatId: String, raw: String, idPrefix: String, final: Bool = false) {
        guard var msgs = extraMessages[chatId], let last = msgs.indices.last,
              msgs[last].role == .assistant else { return }

        let result = ArtifactParser.process(raw, idPrefix: idPrefix)
        msgs[last].text = result.visibleText
        msgs[last].isDraftingArtifact = result.isDraftingArtifact && !final
        var firstRef: ArtifactRef?
        for parsed in result.artifacts {
            let ref = store(parsed)
            if firstRef == nil { firstRef = ref }
        }
        if let firstRef {
            msgs[last].artifact = firstRef
            msgs[last].source = "Saved to your \(firstRef.type.libraryName) library"
        }
        if final, msgs[last].text.isEmpty, msgs[last].artifact == nil {
            msgs[last].text = "…"  // model produced nothing visible
        }
        extraMessages[chatId] = msgs

        // Throttle auto-scroll bumps to ~8/s.
        let now = Date()
        if final || now.timeIntervalSince(lastScrollBump) > 0.12 {
            lastScrollBump = now
            scrollTick += 1
        }
    }

    /// Conversation as role/content turns: system prompt + seeded sample
    /// history + live messages. Artifact cards contribute their titles.
    private func buildTurns(chatId: String) -> [ChatTurn] {
        let chatContext = contextByChat[chatId] ?? (classroom.isDemo ? SampleData.chatMeta[chatId] : nil)
        var turns: [ChatTurn] = [ChatTurn(role: .system, content: systemPrompt(chatContext: chatContext))]
        let history = (SampleData.baseMessages[chatId] ?? []) + (extraMessages[chatId] ?? [])
        for msg in history {
            var content = msg.text
            if let hidden = msg.hiddenContext {
                content += (content.isEmpty ? "" : "\n\n") + hidden
            }
            if let ref = msg.artifact, let art = artifact(for: ref) {
                content += "\n[Shared artifact: \(art.title)]"
            }
            guard !content.trimmingCharacters(in: .whitespaces).isEmpty else { continue }
            turns.append(ChatTurn(role: msg.role == .user ? .user : .assistant, content: content))
        }
        return turns
    }

    func systemPrompt(chatContext: String?) -> String {
        let c = classroom
        var p = "You are the teaching assistant inside \(AppInfo.productName), a planning app used by "
        if c.teacherName.isEmpty {
            p += "a teacher."
        } else {
            p += c.teacherName
            if !c.subject.isEmpty { p += ", a \(c.subject.lowercased()) teacher" }
            if !c.school.isEmpty { p += " at \(c.school)" }
            p += "."
        }
        p += " You help with lesson planning, differentiation, rubrics, activities, student support plans, and family communication.\n"

        let realClasses = c.classes.filter { !$0.name.isEmpty }
        if !realClasses.isEmpty {
            p += "\nClassroom context:\n"
            for cls in realClasses {
                p += "- \(cls.name)"
                if !cls.gradeLevel.isEmpty { p += " (\(cls.gradeLevel))" }
                if !cls.notes.isEmpty { p += " — \(cls.notes)" }
                p += "\n"
                for s in cls.students where !s.name.isEmpty {
                    p += "  - Student \(s.name)" + (s.notes.isEmpty ? "" : ": \(s.notes)") + "\n"
                }
            }
        }
        let rubricTitles = allRubrics.prefix(6).map(\.title).joined(separator: ", ")
        let activityTitles = allActivities.prefix(6).map(\.title).joined(separator: ", ")
        if !rubricTitles.isEmpty { p += "- Rubric library: \(rubricTitles).\n" }
        if !activityTitles.isEmpty { p += "- Activity library: \(activityTitles).\n" }
        p += """
        - Portraits of a Graduate (PoG): competency portraits with 5 competencies \
        (Critical Thinking, Effective Communication, Collaboration, Self-Direction, Civic Engagement).

        Style: be concise and practical. Prefer short lists over long prose. Give concrete, \
        classroom-ready suggestions. Don't invent data about specific students beyond the context above.

        Creating artifacts: when the teacher asks you to create, draft, or update a rubric, an activity \
        (lesson/stations/exit ticket), or a Portrait of a Graduate (PoG), reply with ONE short sentence, \
        then a code block starting with ```artifact containing ONLY the JSON, then stop. \
        Never describe the artifact's contents outside the block. Exactly one artifact per reply. \
        JSON shapes (follow them exactly):
        Rubric (3-5 criteria, each with exactly 4 level descriptions ordered weakest to strongest: Beginning, Developing, Proficient, Advanced):
        {"type":"rubric","title":"...","subtitle":"one line","criteria":[{"name":"...","levels":["...","...","...","..."]}]}
        Activity (3-6 steps):
        {"type":"activity","title":"...","subject":"Biology","duration":"45 min","format":"Stations","description":"one line","steps":["...","..."]}
        Quiz or exit ticket (3-10 questions; "choices" optional — omit for short answer; keep answers brief):
        {"type":"quiz","title":"...","subtitle":"one line","questions":[{"prompt":"...","choices":["...","...","...","..."],"answer":"B"},{"prompt":"...","answer":"short answer"}]}
        Email to families (write the full email in "body" with newlines; warm, plain language):
        {"type":"email","title":"Subject line","subtitle":"who it's for","body":"Dear families,\\n..."}
        Lesson plan: use the activity type with "format":"Lesson plan" and the steps as the agenda.
        PoG (exactly these 5 competencies: Critical Thinking, Effective Communication, Collaboration, Self-Direction, Civic Engagement; level is 1-5):
        {"type":"pog","title":"Student Name — PoG Draft","subtitle":"one line","competencies":[{"name":"...","description":"one line","level":3}]}
        Only the types rubric, activity, quiz, email, and pog exist. For every other request — questions, \
        summaries, advice, anything conversational — reply in plain text with NO code block.
        When the teacher asks to change or revise an existing artifact, emit the complete revised \
        artifact using EXACTLY the same title — the app replaces the old version.
        """
        if let chatContext {
            p += "\nThis conversation is about: \(chatContext)."
        }
        return p
    }

    // MARK: - Search

    struct SearchHit: Identifiable {
        var id: String { kind + title }
        var kind: String
        var title: String
        var meta: String
        var action: () -> Void
    }

    var searchHits: [SearchHit] {
        var idx: [SearchHit] = []
        for (chat, group) in allChats {
            idx.append(SearchHit(kind: "Chats", title: chat.title, meta: group) { [weak self] in
                self?.searchOpen = false
                self?.openChat(chat.id)
            })
        }
        for r in allRubrics {
            idx.append(SearchHit(kind: "Rubrics", title: r.title, meta: r.meta) { [weak self] in
                self?.searchOpen = false
                self?.setView(.rubrics)
                self?.openPreview(ArtifactRef(type: .rubric, id: r.id))
            })
        }
        for a in allActivities {
            idx.append(SearchHit(kind: "Activities", title: a.title, meta: a.meta) { [weak self] in
                self?.searchOpen = false
                self?.setView(.activities)
                self?.openPreview(ArtifactRef(type: .activity, id: a.id))
            })
        }
        for p in allPogs {
            idx.append(SearchHit(kind: "PoGs", title: p.title, meta: p.meta) { [weak self] in
                self?.searchOpen = false
                self?.setView(.pogs)
                self?.openPreview(ArtifactRef(type: .pog, id: p.id))
            })
        }
        for q in allQuizzes {
            idx.append(SearchHit(kind: "Quizzes", title: q.title, meta: q.meta) { [weak self] in
                self?.searchOpen = false
                self?.setView(.quizzes)
                self?.openPreview(ArtifactRef(type: .quiz, id: q.id))
            })
        }
        for e in allEmails {
            idx.append(SearchHit(kind: "Emails", title: e.title, meta: e.meta) { [weak self] in
                self?.searchOpen = false
                self?.openPreview(ArtifactRef(type: .email, id: e.id))
            })
        }
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        if q.isEmpty { return Array(idx.prefix(8)) }
        return idx.filter { ($0.title + " " + $0.meta).lowercased().contains(q) }
    }

    var searchGroups: [(label: String, items: [SearchHit])] {
        let hits = searchHits
        return ["Chats", "Rubrics", "Activities", "PoGs", "Quizzes", "Emails"]
            .map { k in (k, hits.filter { $0.kind == k }) }
            .filter { !$0.1.isEmpty }
    }
}
