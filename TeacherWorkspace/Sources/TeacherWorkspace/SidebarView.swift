import SwiftUI

struct SidebarView: View {
    @EnvironmentObject var state: AppState

    private var t: Theme { state.theme }

    var body: some View {
        VStack(spacing: 0) {
            // Space under the native traffic lights.
            titleRow
                .padding(.top, 38)
            navButtons
            chatList
            footer
        }
        .frame(width: 272)
        .background(t.side)
        .overlay(alignment: .trailing) {
            Rectangle().fill(t.border).frame(width: 1)
        }
        .overlay(alignment: .bottom) {
            if state.settingsOpen {
                SettingsPopover()
                    .padding(.horizontal, 12)
                    .padding(.bottom, 62)
            }
        }
    }

    private var titleRow: some View {
        HStack(spacing: 8) {
            Text("Teacher Workspace")
                .font(.system(size: 16, weight: .bold))
                .kerning(-0.16)
            Image(systemName: "chevron.down")
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(t.dim)
            Spacer()
            Button {
                state.toggleSearch()
            } label: {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(t.sub)
                    .frame(width: 28, height: 28)
            }
            .buttonStyle(.plain)
            .hoverHighlight(radius: 7, hover: t.hover)
            .help("Search (⌘K)")
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 8)
    }

    private var navButtons: some View {
        VStack(spacing: 1) {
            navButton("New chat", icon: "square.and.pencil", isActive: false) { state.newChat() }
            navButton("Rubrics", icon: "tablecells", isActive: state.view == .rubrics) { state.setView(.rubrics) }
            navButton("Activities", icon: "triangle", isActive: state.view == .activities) { state.setView(.activities) }
            navButton("Portraits of a Graduate", icon: "person", isActive: state.view == .pogs) { state.setView(.pogs) }
            navButton("Plugins", icon: "circle.circle", isActive: state.view == .integrations) { state.setView(.integrations) }
        }
        .padding(.horizontal, 10)
        .padding(.top, 4)
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
            VStack(alignment: .leading, spacing: 0) {
                ForEach(state.sidebarGroups) { group in
                    if group.name == state.firstStudentGroupName {
                        Text("Students")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(t.dim)
                            .padding(.horizontal, 10)
                            .padding(.top, 14)
                    }
                    chatGroup(group)
                }
            }
            .padding(.horizontal, 10)
            .padding(.bottom, 12)
        }
        .frame(maxHeight: .infinity)
    }

    private func chatGroup(_ group: ChatGroup) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(group.name)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(t.dim)
                .padding(.horizontal, 10)
                .padding(.top, 2)
                .padding(.bottom, 4)
            ForEach(group.chats) { chat in
                chatRow(chat)
            }
        }
        .padding(.top, 14)
    }

    private func chatRow(_ chat: Chat) -> some View {
        let isActive = state.view == .chat && state.activeChat == chat.id
        return Button {
            state.openChat(chat.id)
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "folder")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(t.dim)
                    .frame(width: 14)
                Text(chat.title)
                    .font(.system(size: 13))
                    .foregroundStyle(t.text)
                    .lineLimit(1)
                    .truncationMode(.tail)
                Spacer(minLength: 0)
            }
            .padding(.vertical, 7)
            .padding(.horizontal, 10)
            .contentShape(RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
        .hoverHighlight(radius: 8, hover: t.hover, base: isActive ? t.active : .clear)
    }

    private var footer: some View {
        HStack(spacing: 10) {
            Text("DA")
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(t.accent)
                .frame(width: 30, height: 30)
                .background(Circle().fill(t.accentSoft))
            VStack(alignment: .leading, spacing: 0) {
                Text("Dana Alvarez")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(t.text)
                Text("Crestview High · Science")
                    .font(.system(size: 11.5))
                    .foregroundStyle(t.dim)
            }
            Spacer(minLength: 0)
            Button {
                state.settingsOpen.toggle()
            } label: {
                Image(systemName: "slider.horizontal.3")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(t.sub)
                    .frame(width: 30, height: 30)
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
            Button {
                state.setView(.integrations)
                state.settingsOpen = false
            } label: {
                Text("Manage plugins & connections")
                    .font(.system(size: 13))
                    .foregroundStyle(t.sub)
            }
            .buttonStyle(.plain)
            .padding(.vertical, 2)
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
