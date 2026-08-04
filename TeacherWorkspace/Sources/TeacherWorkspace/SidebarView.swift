import SwiftUI

struct SidebarView: View {
    @EnvironmentObject var state: AppState
    @StateObject private var collapse = SidebarCollapseState()
    /// Folder currently being renamed inline (also used right after "+").
    @State private var renamingFolder: String?
    @State private var draftFolderName = ""
    @FocusState private var folderNameFocused: Bool
    /// Folder id (or "all") the dragged chat is hovering over.
    @State private var dropTarget: String?
    /// Sidebar width when the current resize drag began.
    @State private var dragStartWidth: CGFloat?

    private var t: Theme { state.theme }

    var body: some View {
        VStack(spacing: 0) {
            // Space under the native traffic lights.
            titleRow
                .padding(.top, 38)
            // Only New stays pinned — everything else scrolls.
            navButton("New", icon: "square.and.pencil", isActive: false) { state.newChat() }
                .padding(.horizontal, 10)
                .padding(.top, 4)
            chatList
            footer
        }
        .frame(width: min(Self.maxWidth, max(Self.minWidth, state.sidebarWidth)))
        .background(t.side)
        .overlay(alignment: .trailing) { resizeHandle }
        .overlay(alignment: .bottom) {
            if state.settingsOpen {
                SettingsPopover()
                    .padding(.horizontal, 12)
                    .padding(.bottom, 62)
            }
        }
    }

    private static let minWidth: CGFloat = 200
    private static let maxWidth: CGFloat = 460

    /// Drag the sidebar's right edge to resize it — the mirror of the preview
    /// panel's handle, so both edges of the window behave the same way.
    private var resizeHandle: some View {
        ZStack {
            Rectangle().fill(t.border).frame(width: 1)
        }
        .frame(width: 8)
        .frame(maxHeight: .infinity)
        .contentShape(Rectangle())
        .gesture(
            DragGesture(minimumDistance: 1, coordinateSpace: .global)
                .onChanged { value in
                    if dragStartWidth == nil { dragStartWidth = state.sidebarWidth }
                    let proposed = (dragStartWidth ?? 272) + value.translation.width
                    state.sidebarWidth = min(Self.maxWidth, max(Self.minWidth, proposed))
                }
                .onEnded { _ in dragStartWidth = nil }
        )
        .onHover { inside in
            if inside { NSCursor.resizeLeftRight.push() } else { NSCursor.pop() }
        }
        .help("Drag to resize")
    }

    private var titleRow: some View {
        HStack(spacing: 8) {
            AppIconMark(size: 26)
                // The .icns keeps Apple's 10% margin around the plate, so pull
                // the name back in to sit 8pt from the artwork, not the canvas.
                .padding(.trailing, -5)
            Text(AppInfo.productName)
                .font(.system(size: 16, weight: .bold))
                .kerning(-0.16)
                .lineLimit(1)
                .truncationMode(.tail)
            VersionBadge()
            Spacer()
            Button {
                state.toggleSearch()
            } label: {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(t.sub)
                    .frame(width: 30, height: 30)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .hoverHighlight(radius: 7, hover: t.hover)
            .help("Search (⌘K)")
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 8)
    }

    /// Library/navigation entries — scroll with the chat list.
    private var libraryButtons: some View {
        VStack(spacing: 1) {
            navButton("My Classroom", icon: "person.2", isActive: state.view == .classroom) { state.setView(.classroom) }
            navButton("Rubrics", icon: "tablecells", isActive: state.view == .rubrics) { state.setView(.rubrics) }
            navButton("Activities", icon: "triangle", isActive: state.view == .activities) { state.setView(.activities) }
            navButton("Portraits of a Graduate", icon: "person", isActive: state.view == .pogs) { state.setView(.pogs) }
            navButton("Quizzes", icon: "checklist", isActive: state.view == .quizzes) { state.setView(.quizzes) }
            navButton("Plugins", icon: "circle.circle", isActive: state.view == .integrations) { state.setView(.integrations) }
        }
    }

    private func navButton(_ title: String, icon: String, isActive: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 11) {
                Image(systemName: icon)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(t.sub)
                    .frame(width: 16)
                Text(title)
                    .font(.system(size: 13.5, weight: .medium))
                    .foregroundStyle(t.text)
                Spacer(minLength: 0)
            }
            .padding(.vertical, 8)
            .padding(.horizontal, 10)
            .contentShape(RoundedRectangle(cornerRadius: 9))
        }
        .buttonStyle(.plain)
        .hoverHighlight(radius: 9, hover: t.hover, base: isActive ? t.active : .clear)
    }

    private var chatList: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 1) {
                libraryButtons
                foldersSection
                DisclosureRow(title: "ALL CHATS", isExpanded: allChatsExpanded,
                              isSectionHeader: true, theme: t) {
                    collapse.toggle("section.all", default: true)
                }
                .padding(.top, 12)
                // Dropping here files a chat out of whatever folder it's in.
                .dropDestination(for: String.self) { ids, _ in
                    for id in ids {
                        state.moveChat(id, toFolder: nil)
                        // Dragging out of Archived puts the chat back in play.
                        state.unarchiveChat(id)
                    }
                    return !ids.isEmpty
                } isTargeted: { dropTarget = $0 ? "all" : (dropTarget == "all" ? nil : dropTarget) }
                .background(dropHighlight(active: dropTarget == "all"))
                if allChatsExpanded {
                    if state.unfiledChats.isEmpty {
                        emptyHint(state.sidebarChats.isEmpty
                                  ? "No chats yet — start one above."
                                  : "Every chat is in a folder.")
                    }
                    ForEach(state.unfiledChats) { chat in
                        chatRow(chat)
                    }
                }
                archivedSection
            }
            .padding(.horizontal, 10)
            .padding(.top, 10)
            .padding(.bottom, 12)
        }
        .frame(maxHeight: .infinity)
    }

    @ViewBuilder
    private var foldersSection: some View {
        DisclosureRow(title: "FOLDERS", isExpanded: foldersExpanded,
                      isSectionHeader: true, theme: t) {
            collapse.toggle("section.folders", default: true)
        } trailing: {
            Button {
                if !foldersExpanded { collapse.toggle("section.folders", default: true) }
                let id = state.addFolder()
                renamingFolder = id
                draftFolderName = "New folder"
            } label: {
                Image(systemName: "plus")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(t.sub)
                    .frame(width: 18, height: 18)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .hoverHighlight(radius: 5, hover: t.active)
            .help("New folder")
        }
        .padding(.top, 12) // gap below the library buttons
        if foldersExpanded {
            if state.folders.isEmpty {
                emptyHint("No folders yet — use + to group your chats.")
            }
            ForEach(state.folders) { folder in
                folderRow(folder)
            }
        }
    }

    /// Only appears once something is archived — an empty Archived section
    /// would just be clutter in a sidebar the teacher lives in.
    @ViewBuilder
    private var archivedSection: some View {
        let archived = state.archivedChatList
        if !archived.isEmpty {
            DisclosureRow(title: "ARCHIVED", isExpanded: archivedExpanded,
                          isSectionHeader: true, theme: t) {
                collapse.toggle("section.archived", default: false)
            } trailing: {
                Text("\(archived.count)")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(t.dim)
            }
            .padding(.top, 12)
            if archivedExpanded {
                ForEach(archived) { chat in
                    chatRow(chat, archived: true)
                }
            }
        }
    }

    private var archivedExpanded: Bool { collapse.isExpanded("section.archived", default: false) }

    private func emptyHint(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 12))
            .foregroundStyle(t.dim)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
    }

    private func dropHighlight(active: Bool) -> some View {
        RoundedRectangle(cornerRadius: 8)
            .fill(active ? t.accentSoft : .clear)
            .overlay(RoundedRectangle(cornerRadius: 8)
                .stroke(active ? t.accent : .clear, lineWidth: 1))
    }

    private var foldersExpanded: Bool { collapse.isExpanded("section.folders", default: true) }
    private var allChatsExpanded: Bool { collapse.isExpanded("section.all", default: true) }

    @ViewBuilder
    private func folderRow(_ folder: Folder) -> some View {
        let key = "folder.\(folder.id)"
        let expanded = collapse.isExpanded(key, default: false)
        let chats = state.chats(inFolder: folder.id)
        if renamingFolder == folder.id {
            TextField("Folder name", text: $draftFolderName)
                .textFieldStyle(.roundedBorder)
                .font(.system(size: 12.5))
                .focused($folderNameFocused)
                .onSubmit(commitFolderName)
                .onExitCommand(perform: commitFolderName)
                .onAppear { folderNameFocused = true }
                .padding(.horizontal, 10)
                .padding(.vertical, 3)
        } else {
            DisclosureRow(title: folder.name, icon: "folder", isExpanded: expanded, theme: t) {
                collapse.toggle(key, default: false)
            } trailing: {
                Text("\(chats.count)")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(t.dim)
            }
            .contextMenu {
                Button("Rename") {
                    draftFolderName = folder.name
                    renamingFolder = folder.id
                }
                Button("Delete folder", role: .destructive) { state.deleteFolder(folder.id) }
            }
            .dropDestination(for: String.self) { ids, _ in
                for id in ids {
                    state.moveChat(id, toFolder: folder.id)
                    state.unarchiveChat(id)
                }
                if !ids.isEmpty, !expanded { collapse.toggle(key, default: false) }
                return !ids.isEmpty
            } isTargeted: { dropTarget = $0 ? folder.id : (dropTarget == folder.id ? nil : dropTarget) }
            .background(dropHighlight(active: dropTarget == folder.id))
        }
        if expanded {
            if chats.isEmpty {
                emptyHint("Empty — drag a chat here.")
            }
            ForEach(chats) { chat in
                chatRow(chat, indented: true)
            }
        }
    }

    private func commitFolderName() {
        if let id = renamingFolder { state.renameFolder(id, to: draftFolderName) }
        renamingFolder = nil
        folderNameFocused = false
    }

    private func chatRow(_ chat: Chat, indented: Bool = false, archived: Bool = false) -> some View {
        ChatRow(chat: chat, indented: indented, archived: archived, theme: t)
        .draggable(chat.id) {
            // Drag preview — the row itself would drag its full width.
            Label(chat.title, systemImage: "bubble.left")
                .font(.system(size: 12))
                .padding(6)
        }
        .contextMenu {
            if archived {
                Button("Unarchive") { state.unarchiveChat(chat.id) }
            } else {
                // Same moves as dragging, for anyone who'd rather not drag.
                Menu("Move to") {
                    ForEach(state.folders) { folder in
                        Button(folder.name) { state.moveChat(chat.id, toFolder: folder.id) }
                            .disabled(state.chatFolder[chat.id] == folder.id)
                    }
                    if !state.folders.isEmpty { Divider() }
                    Button("New folder…") {
                        let id = state.addFolder()
                        state.moveChat(chat.id, toFolder: id)
                        draftFolderName = "New folder"
                        renamingFolder = id
                    }
                    if state.chatFolder[chat.id] != nil {
                        Divider()
                        Button("Remove from folder") { state.moveChat(chat.id, toFolder: nil) }
                    }
                }
                Divider()
                Button("Archive") { state.archiveChat(chat.id) }
            }
        }
    }

    private var footer: some View {
        let c = state.classroom
        let initials = c.teacherName.split(separator: " ").prefix(2).compactMap { $0.first.map(String.init) }.joined()
        let detail = [c.school, c.subject].filter { !$0.isEmpty }.joined(separator: " · ")
        return HStack(spacing: 10) {
            // The profile itself opens My Classroom — it's the identity the
            // teacher will want to edit when they click their own name.
            Button {
                state.setView(.classroom)
            } label: {
                HStack(spacing: 10) {
                    Text(initials.isEmpty ? "🍎" : initials)
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(t.accent)
                        .frame(width: 30, height: 30)
                        .background(Circle().fill(t.accentSoft))
                    VStack(alignment: .leading, spacing: 0) {
                        Text(c.teacherName.isEmpty ? "Set up your classroom" : c.teacherName)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(t.text)
                        if !detail.isEmpty {
                            Text(detail)
                                .font(.system(size: 11.5))
                                .foregroundStyle(t.dim)
                        }
                    }
                    Spacer(minLength: 0)
                }
                .padding(4)
                .contentShape(RoundedRectangle(cornerRadius: 8))
            }
            .buttonStyle(.plain)
            .hoverHighlight(radius: 8, hover: t.hover, base: state.view == .classroom ? t.active : .clear)
            .help("Open My Classroom")
            Button {
                state.settingsOpen.toggle()
            } label: {
                Image(systemName: "slider.horizontal.3")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(t.sub)
                    .frame(width: 32, height: 32)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .hoverHighlight(radius: 8, hover: t.hover, base: state.settingsOpen ? t.active : .clear)
            .help("Settings")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .overlay(alignment: .top) {
            Rectangle().fill(t.border).frame(height: 1)
        }
    }
}

/// The app icon, shown beside the name in the sidebar. Reads the .icns that
/// make-app.sh copies into Contents/Resources, so it always matches whatever
/// `swift scripts/make-icon.swift` last produced. Unbundled dev runs have no
/// Resources directory — there it renders nothing rather than the generic
/// placeholder icon AppKit would hand back.
private struct AppIconMark: View {
    var size: CGFloat

    private static let image: NSImage? = {
        guard let url = Bundle.main.url(forResource: "AppIcon", withExtension: "icns") else { return nil }
        return NSImage(contentsOf: url)
    }()

    var body: some View {
        if let image = Self.image {
            Image(nsImage: image)
                .resizable()
                .interpolation(.high)
                .frame(width: size, height: size)
                .accessibilityHidden(true)
        }
    }
}

/// Version chip beside the app name. Hovering turns it into a
/// "Check for updates" button (Sparkle's standard flow: either an
/// up-to-date dialog or the download/install sheet). Dev builds have no
/// update feed, so there it stays a plain version label.
private struct VersionBadge: View {
    @EnvironmentObject var state: AppState
    @State private var hovering = false
    private var t: Theme { state.theme }
    private var canCheck: Bool { UpdateChecker.shared.isAvailable }
    private var active: Bool { hovering && canCheck }

    var body: some View {
        Button {
            UpdateChecker.shared.checkForUpdates()
        } label: {
            Text(active ? "Check for updates" : "v\(AppInfo.version)")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(active ? t.accent : t.dim)
                .padding(.vertical, 2)
                .padding(.horizontal, 6)
                .background(Capsule().fill(active ? t.accentSoft : t.hover))
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .disabled(!canCheck)
        .onHover { hovering = $0 }
        .help(canCheck ? "Check for updates" : "Version \(AppInfo.version) — updates run from the installed app")
        .animation(.easeOut(duration: 0.12), value: active)
    }
}

struct SettingsPopover: View {
    @EnvironmentObject var state: AppState
    private var t: Theme { state.theme }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("APPEARANCE")
                .font(.system(size: 11, weight: .bold))
                .kerning(0.66)
                .foregroundStyle(t.dim)
            HStack(spacing: 4) {
                themeButton("Light", name: "light")
                themeButton("Dark", name: "dark")
            }
            .padding(3)
            .background(RoundedRectangle(cornerRadius: 9).fill(t.bg))
            Rectangle().fill(t.border).frame(height: 1)
                .padding(.horizontal, -12)
                .padding(.top, 2)
            HStack(alignment: .top, spacing: 6) {
                Image(systemName: "lock.shield")
                    .font(.system(size: 11))
                    .foregroundStyle(t.green)
                    .padding(.top, 1)
                Text("Private by design — the AI model runs entirely on this Mac. Chats, rosters, and student notes never leave it.")
                    .font(.system(size: 11))
                    .foregroundStyle(t.sub)
                    .fixedSize(horizontal: false, vertical: true)
            }
            // Reads as a row you can click, not a line of prose: same icon,
            // weight and hover fill as the sidebar nav, plus a chevron for
            // "this goes somewhere". Negative inset lets the fill run wider
            // than the popover's text padding.
            Button {
                state.setView(.integrations)
                state.settingsOpen = false
            } label: {
                HStack(spacing: 9) {
                    Image(systemName: "circle.circle")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(t.sub)
                        .frame(width: 16)
                    Text("Plugins & Skills")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(t.text)
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.right")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(t.dim)
                }
                .padding(.vertical, 7)
                .padding(.horizontal, 8)
                .contentShape(RoundedRectangle(cornerRadius: 8))
            }
            .buttonStyle(.plain)
            .hoverHighlight(radius: 8, hover: t.hover)
            .padding(.horizontal, -4)
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(t.card)
                .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(t.border))
                .shadow(color: .black.opacity(t.isDark ? 0.55 : 0.25), radius: 30, y: 20)
        )
    }

    private func themeButton(_ label: String, name: String) -> some View {
        let selected = state.themeName == name
        return Button {
            state.themeName = name
        } label: {
            Text(label)
                .font(.system(size: 12.5, weight: .semibold))
                .foregroundStyle(selected ? t.text : t.sub)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 6)
                .background(RoundedRectangle(cornerRadius: 7).fill(selected ? t.active : .clear))
                .contentShape(RoundedRectangle(cornerRadius: 7))
        }
        .buttonStyle(.plain)
    }
}
