import SwiftUI

struct ContentView: View {
    @EnvironmentObject var state: AppState
    private var t: Theme { state.theme }
    // Inline chat-title rename (double-click the header title).
    @State private var editingTitle = false
    @State private var titleDraft = ""
    @FocusState private var titleFieldFocused: Bool

    var body: some View {
        ZStack {
            if state.needsModelSetup {
                // First run, no model anywhere: nothing in the app can work,
                // so setup takes over. Model *upgrades* never land here.
                ModelGateView()
            } else {
                HStack(spacing: 0) {
                    SidebarView()
                    VStack(spacing: 0) {
                        header
                        HStack(spacing: 0) {
                            mainContent
                                .frame(maxWidth: .infinity, maxHeight: .infinity)
                            if state.previewOpen {
                                PreviewPanel()
                            }
                        }
                    }
                    .frame(maxWidth: .infinity)
                }
                .background(t.bg)
                .animation(.easeOut(duration: 0.15), value: state.previewOpen)

                if state.scheduleOpen, state.showsDemoPlugins {
                    SchedulePopover()
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                        .padding(.top, 84) // just below the 28 + 50pt header
                        .padding(.trailing, 56)
                }

                if state.searchOpen {
                    SearchOverlay()
                }
            }

            // The tour overlays the gate on a true first launch — teachers
            // see what the app is before being asked for a 1.2 GB download.
            if state.onboardingOpen {
                OnboardingView()
            }
        }
        .foregroundStyle(t.text)
        .font(.system(size: 14))
        .ignoresSafeArea()
        // Clicking anywhere outside the settings/schedule popovers dismisses
        // them; an in-progress rename commits with what was typed.
        .onTapGesture {
            if state.settingsOpen { state.settingsOpen = false }
            if state.scheduleOpen { state.scheduleOpen = false }
            if editingTitle { commitTitleEdit() }
        }
    }

    /// Renaming only makes sense on an open chat, not library pages.
    private var canRenameTitle: Bool { state.view == .chat && state.activeChat != nil }

    private var header: some View {
        HStack(spacing: 10) {
            if editingTitle {
                ZStack(alignment: .leading) {
                    // Invisible twin sizes the field to the typed text, so the
                    // box hugs the title and grows as you type.
                    Text(titleDraft.isEmpty ? "Chat title" : titleDraft)
                        .font(.system(size: 14.5, weight: .semibold))
                        .lineLimit(1)
                        .opacity(0)
                    TextField("Chat title", text: $titleDraft)
                        .textFieldStyle(.plain)
                        .font(.system(size: 14.5, weight: .semibold))
                        .focused($titleFieldFocused)
                        .onSubmit { commitTitleEdit() }
                        .onExitCommand { editingTitle = false }
                }
                .padding(.vertical, 2)
                .padding(.horizontal, 7)
                .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(t.input))
                .overlay(RoundedRectangle(cornerRadius: 7, style: .continuous).stroke(t.accent, lineWidth: 1))
                .frame(maxWidth: 480, alignment: .leading)
                .onChange(of: titleFieldFocused) { _, focused in
                    // Clicking away commits, like Finder renames.
                    if !focused, editingTitle { commitTitleEdit() }
                }
            } else {
                Text(state.headerTitle)
                    .font(.system(size: 14.5, weight: .semibold))
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .onTapGesture(count: 2) { startTitleEdit() }
                    .help(canRenameTitle ? "Double-click to rename" : "")
            }
            if let chip = state.headerChip {
                Text(chip)
                    .font(.system(size: 11.5, weight: .semibold))
                    .foregroundStyle(t.accent)
                    .padding(.vertical, 2)
                    .padding(.horizontal, 9)
                    .background(Capsule().fill(t.accentSoft))
            }
            Spacer()
            if state.showsDemoPlugins {
                Button {
                    state.scheduleOpen.toggle()
                } label: {
                    Image(systemName: "calendar")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(state.scheduleOpen ? t.accent : t.sub)
                        .frame(width: 32, height: 32)
                        .contentShape(Rectangle())
                        .overlay(alignment: .topTrailing) {
                            // Mock "connected" status dot for the demo plugin.
                            Circle().fill(t.green)
                                .frame(width: 6, height: 6)
                                .padding(6)
                        }
                }
                .buttonStyle(.plain)
                .hoverHighlight(radius: 8, hover: t.hover)
                .help("Today's schedule — Google Calendar")
            }
            Button {
                state.showOnboarding()
            } label: {
                Image(systemName: "questionmark.circle")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(t.sub)
                    .frame(width: 32, height: 32)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .hoverHighlight(radius: 8, hover: t.hover)
            .help("Welcome tour")
            Button {
                state.togglePreview()
            } label: {
                Image(systemName: "sidebar.trailing")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(t.sub)
                    .frame(width: 32, height: 32)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .hoverHighlight(radius: 8, hover: t.hover)
            .help("Toggle preview panel")
        }
        .padding(.horizontal, 20)
        .frame(height: 50)
        .padding(.top, 28) // clearance under the hidden title bar
        // Abandon an in-progress rename if the chat or page changes under it.
        .onChange(of: state.activeChat) { _, _ in editingTitle = false }
        .onChange(of: state.view) { _, _ in editingTitle = false }
    }

    private func startTitleEdit() {
        guard canRenameTitle else { return }
        titleDraft = state.headerTitle
        editingTitle = true
        titleFieldFocused = true
    }

    private func commitTitleEdit() {
        guard editingTitle else { return }
        editingTitle = false
        if let id = state.activeChat {
            state.renameChat(id, to: titleDraft)
        }
    }

    @ViewBuilder
    private var mainContent: some View {
        switch state.view {
        case .chat: ChatView()
        case .rubrics: RubricsView()
        case .activities: ActivitiesView()
        case .pogs: PogsView()
        case .quizzes: QuizzesView()
        case .integrations: IntegrationsView()
        case .classroom: ClassroomView()
        }
    }
}

/// Demo Google Calendar dropdown — mock-connected plugin showing today's
/// schedule (SampleData, anchored to the current time so it looks live).
struct SchedulePopover: View {
    @EnvironmentObject var state: AppState
    private var t: Theme { state.theme }
    private let events = SampleData.todaysSchedule()
    private let now = Date()

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                Text("Today’s schedule")
                    .font(.system(size: 13, weight: .semibold))
                Spacer()
                Circle().fill(t.green).frame(width: 7, height: 7)
                Text("Google Calendar")
                    .font(.system(size: 11.5))
                    .foregroundStyle(t.sub)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            Divider().overlay(t.border)
            VStack(alignment: .leading, spacing: 2) {
                ForEach(events) { e in
                    row(e)
                }
            }
            .padding(8)
        }
        .frame(width: 320)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(t.card))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(t.border))
        .shadow(color: .black.opacity(t.isDark ? 0.4 : 0.15), radius: 18, y: 8)
        // Swallow taps so the outside-click dismissal doesn't fire.
        .onTapGesture {}
    }

    private func row(_ e: SampleData.CalendarEvent) -> some View {
        let isNow = e.start <= now && now < e.end
        return HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(Self.timeFmt.string(from: e.start))
                .font(.system(size: 11.5, weight: .medium).monospacedDigit())
                .foregroundStyle(isNow ? t.accent : t.dim)
                .frame(width: 58, alignment: .trailing)
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 6) {
                    Text(e.title)
                        .font(.system(size: 12.5, weight: .semibold))
                        .foregroundStyle(t.text)
                    if isNow {
                        Text("NOW")
                            .font(.system(size: 9, weight: .bold))
                            .kerning(0.5)
                            .foregroundStyle(t.accent)
                            .padding(.vertical, 1.5)
                            .padding(.horizontal, 5)
                            .background(Capsule().fill(t.accentSoft))
                    }
                }
                Text(e.detail)
                    .font(.system(size: 11.5))
                    .foregroundStyle(t.sub)
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 8)
        .background(RoundedRectangle(cornerRadius: 8)
            .fill(isNow ? t.accentSoft.opacity(0.6) : .clear))
    }

    private static let timeFmt: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "h:mm a"
        return f
    }()
}
