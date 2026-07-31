import SwiftUI

enum MainView: Hashable {
    case chat, rubrics, activities, pogs, integrations
}

@MainActor
final class AppState: ObservableObject {
    @Published var view: MainView = .chat
    @Published var activeChat: String? = "c1"
    @Published var themeName: String = "dark"
    @Published var settingsOpen = false
    @Published var preview: ArtifactRef?
    @Published var lastPreview: ArtifactRef?
    @Published var previewWide = false
    @Published var searchOpen = false
    @Published var query = ""
    @Published var draft = ""
    @Published var extraMessages: [String: [Message]] = [:]
    @Published var extraChats: [Chat] = []
    @Published var pogLevels: [String: Int] = [:]
    @Published var connections: [String: Bool] = [
        "classroom": true, "calendar": true, "drive": true,
        "sis": true, "gmail": true, "seesaw": false, "canvas": false,
    ]
    /// Bumped after sending so the chat scrolls to the newest message.
    @Published var scrollTick = 0

    var theme: Theme { themeName == "light" ? .light : .dark }

    // MARK: - Derived data

    var sidebarGroups: [ChatGroup] {
        var groups: [ChatGroup] = []
        if !extraChats.isEmpty {
            groups.append(ChatGroup(name: "Recent", chats: extraChats))
        }
        groups.append(contentsOf: SampleData.classGroups)
        groups.append(contentsOf: SampleData.studentGroups)
        return groups
    }

    /// Index of the first per-student group in sidebarGroups, for the "Students" header.
    var firstStudentGroupName: String? { SampleData.studentGroups.first?.name }

    var allChats: [(chat: Chat, group: String)] {
        var out: [(Chat, String)] = []
        for g in SampleData.classGroups + SampleData.studentGroups {
            for c in g.chats { out.append((c, g.name)) }
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
        case .integrations: return "Plugins"
        }
    }

    var headerChip: String? {
        guard view == .chat, let id = activeChat else { return nil }
        return SampleData.chatMeta[id] ?? "New"
    }

    var messages: [Message] {
        guard view == .chat, let id = activeChat else { return [] }
        return (SampleData.baseMessages[id] ?? []) + (extraMessages[id] ?? [])
    }

    var isWelcome: Bool { view == .chat && activeChat == nil }

    func artifact(for ref: ArtifactRef) -> (title: String, meta: String)? {
        switch ref.type {
        case .rubric:
            guard let r = SampleData.rubrics.first(where: { $0.id == ref.id }) else { return nil }
            return (r.title, r.meta)
        case .activity:
            guard let a = SampleData.activities.first(where: { $0.id == ref.id }) else { return nil }
            return (a.title, a.meta)
        case .pog:
            guard let p = SampleData.pogs.first(where: { $0.id == ref.id }) else { return nil }
            return (p.title, p.meta)
        }
    }

    // MARK: - Actions

    func setView(_ v: MainView) {
        view = v
        settingsOpen = false
    }

    func openChat(_ id: String) {
        view = .chat
        activeChat = id
        scrollTick += 1
    }

    func newChat() {
        view = .chat
        activeChat = nil
        preview = nil
        settingsOpen = false
    }

    func openPreview(_ ref: ArtifactRef) {
        preview = ref
        lastPreview = ref
    }

    func closePreview() {
        preview = nil
        previewWide = false
    }

    func togglePreview() {
        if preview != nil {
            preview = nil
        } else if let last = lastPreview {
            preview = last
        }
    }

    func toggleSearch() {
        searchOpen.toggle()
        query = ""
    }

    func send() {
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        var chatId = activeChat
        if chatId == nil {
            let id = "new-\(UUID().uuidString)"
            let title = text.count > 42 ? String(text.prefix(42)) + "…" : text
            extraChats.append(Chat(id: id, title: title))
            chatId = id
        }
        guard let id = chatId else { return }
        let reply = Message(
            role: .assistant,
            text: "Here’s a first draft — I pulled context from your Classroom roster and Drive folder. Open the artifact to review and edit it in the preview panel.",
            artifact: ArtifactRef(type: .rubric, id: "r1"),
            source: "Context: Google Classroom · Drive")
        extraMessages[id, default: []].append(contentsOf: [Message(role: .user, text: text), reply])
        draft = ""
        activeChat = id
        view = .chat
        scrollTick += 1
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
        for r in SampleData.rubrics {
            idx.append(SearchHit(kind: "Rubrics", title: r.title, meta: r.meta) { [weak self] in
                self?.searchOpen = false
                self?.setView(.rubrics)
                self?.openPreview(ArtifactRef(type: .rubric, id: r.id))
            })
        }
        for a in SampleData.activities {
            idx.append(SearchHit(kind: "Activities", title: a.title, meta: a.meta) { [weak self] in
                self?.searchOpen = false
                self?.setView(.activities)
                self?.openPreview(ArtifactRef(type: .activity, id: a.id))
            })
        }
        for p in SampleData.pogs {
            idx.append(SearchHit(kind: "PoGs", title: p.title, meta: p.meta) { [weak self] in
                self?.searchOpen = false
                self?.setView(.pogs)
                self?.openPreview(ArtifactRef(type: .pog, id: p.id))
            })
        }
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        if q.isEmpty { return Array(idx.prefix(8)) }
        return idx.filter { ($0.title + " " + $0.meta).lowercased().contains(q) }
    }

    var searchGroups: [(label: String, items: [SearchHit])] {
        let hits = searchHits
        return ["Chats", "Rubrics", "Activities", "PoGs"]
            .map { k in (k, hits.filter { $0.kind == k }) }
            .filter { !$0.1.isEmpty }
    }
}
