import SwiftUI

/// Which sidebar sections and folders the teacher has collapsed.
///
/// Kept in `UserDefaults` rather than the app's JSON store: it's view state,
/// not classroom data, and it shouldn't ride along in the file that holds
/// chats and rosters.
@MainActor
final class SidebarCollapseState: ObservableObject {
    private static let key = "sidebar.disclosure"
    @Published private var states: [String: Bool]

    init() {
        let raw = UserDefaults.standard.data(forKey: Self.key)
        states = raw.flatMap { try? JSONDecoder().decode([String: Bool].self, from: $0) } ?? [:]
    }

    /// `default` applies until the teacher touches the row: top-level sections
    /// start open, individual folders start closed so the sidebar reads as a
    /// short list of names.
    func isExpanded(_ id: String, default fallback: Bool) -> Bool {
        states[id] ?? fallback
    }

    func toggle(_ id: String, default fallback: Bool) {
        states[id] = !isExpanded(id, default: fallback)
        if let data = try? JSONEncoder().encode(states) {
            UserDefaults.standard.set(data, forKey: Self.key)
        }
    }
}

/// A section or folder header that twists open. The whole row is the hit
/// target, so there's no small chevron to aim at.
struct DisclosureRow<Trailing: View>: View {
    var title: String
    var icon: String?
    var isExpanded: Bool
    var isSectionHeader: Bool = false
    var theme: Theme
    var action: () -> Void
    @ViewBuilder var trailing: () -> Trailing

    var body: some View {
        Button(action: action) {
            HStack(spacing: 7) {
                Image(systemName: "chevron.right")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(theme.dim)
                    .rotationEffect(.degrees(isExpanded ? 90 : 0))
                    .frame(width: 10)
                if let icon {
                    Image(systemName: icon)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(theme.dim)
                        .frame(width: 14)
                }
                Text(title)
                    .font(.system(size: isSectionHeader ? 11 : 12.5,
                                  weight: isSectionHeader ? .bold : .semibold))
                    .kerning(isSectionHeader ? 0.6 : 0)
                    .foregroundStyle(isSectionHeader ? theme.dim : theme.sub)
                    .lineLimit(1)
                Spacer(minLength: 4)
                trailing()
            }
            .padding(.vertical, 5)
            .padding(.horizontal, 10)
            .contentShape(RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
        .hoverHighlight(radius: 8, hover: theme.hover)
    }
}

/// A chat in the sidebar. Hovering reveals an archive button on the trailing
/// edge (unarchive, for rows already in Archived).
///
/// The button is a *sibling* of the row button rather than nested inside its
/// label — an inner button never receives the click, the outer one swallows it.
struct ChatRow: View {
    @EnvironmentObject var state: AppState
    var chat: Chat
    var indented: Bool
    var archived: Bool
    var theme: Theme
    @State private var hovering = false

    private var isActive: Bool { state.view == .chat && state.activeChat == chat.id }

    var body: some View {
        ZStack(alignment: .trailing) {
            Button {
                state.openChat(chat.id)
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: archived ? "archivebox" : "bubble.left")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(theme.dim)
                        .frame(width: 14)
                        .padding(.leading, indented ? 17 : 0)
                    Text(chat.title)
                        .font(.system(size: 13))
                        .foregroundStyle(archived ? theme.sub : theme.text)
                        .lineLimit(1)
                        .truncationMode(.tail)
                    // Fixed-width, so a long title gives up room to the badge
                    // rather than the badge shrinking out of legibility.
                    if let status = state.status(for: chat.id) {
                        StatusBadge(status: status, theme: theme, compact: true)
                    }
                    Spacer(minLength: 0)
                }
                .padding(.vertical, 7)
                .padding(.horizontal, 10)
                // Reserve room so a long title truncates before the button
                // rather than running underneath it.
                .padding(.trailing, hovering ? 22 : 0)
                .contentShape(RoundedRectangle(cornerRadius: 8))
            }
            .buttonStyle(.plain)
            if hovering {
                Button {
                    if archived { state.unarchiveChat(chat.id) } else { state.archiveChat(chat.id) }
                } label: {
                    Image(systemName: archived ? "tray.and.arrow.up" : "archivebox")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(theme.sub)
                        .frame(width: 22, height: 22)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .hoverHighlight(radius: 5, hover: theme.active)
                .help(archived ? "Unarchive" : "Archive")
                .padding(.trailing, 6)
            }
        }
        .hoverHighlight(radius: 8, hover: theme.hover, base: isActive ? theme.active : .clear)
        .onHover { hovering = $0 }
    }
}

extension DisclosureRow where Trailing == EmptyView {
    init(title: String, icon: String? = nil, isExpanded: Bool, isSectionHeader: Bool = false,
         theme: Theme, action: @escaping () -> Void) {
        self.init(title: title, icon: icon, isExpanded: isExpanded,
                  isSectionHeader: isSectionHeader, theme: theme, action: action) { EmptyView() }
    }
}
