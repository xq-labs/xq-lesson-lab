import SwiftUI

struct ContentView: View {
    @EnvironmentObject var state: AppState
    private var t: Theme { state.theme }

    var body: some View {
        ZStack {
            HStack(spacing: 0) {
                SidebarView()
                VStack(spacing: 0) {
                    header
                    HStack(spacing: 0) {
                        mainContent
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                        if let ref = state.preview {
                            PreviewPanel(ref: ref)
                        }
                    }
                }
                .frame(maxWidth: .infinity)
            }
            .background(t.bg)
            .animation(.easeOut(duration: 0.15), value: state.preview)
            .animation(.easeOut(duration: 0.15), value: state.previewWide)

            if state.searchOpen {
                SearchOverlay()
            }
        }
        .foregroundStyle(t.text)
        .font(.system(size: 14))
        .ignoresSafeArea()
        // Clicking anywhere outside the settings popover dismisses it.
        .onTapGesture {
            if state.settingsOpen { state.settingsOpen = false }
        }
    }

    private var header: some View {
        HStack(spacing: 10) {
            Text(state.headerTitle)
                .font(.system(size: 14.5, weight: .semibold))
                .lineLimit(1)
                .truncationMode(.tail)
            if let chip = state.headerChip {
                Text(chip)
                    .font(.system(size: 11.5, weight: .semibold))
                    .foregroundStyle(t.accent)
                    .padding(.vertical, 2)
                    .padding(.horizontal, 9)
                    .background(Capsule().fill(t.accentSoft))
            }
            Image(systemName: "ellipsis")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(t.dim)
            Spacer()
            Button {
                state.togglePreview()
            } label: {
                Image(systemName: "sidebar.trailing")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(t.sub)
                    .frame(width: 30, height: 30)
            }
            .buttonStyle(.plain)
            .hoverHighlight(radius: 8, hover: t.hover)
            .help("Toggle preview panel")
        }
        .padding(.horizontal, 20)
        .frame(height: 50)
        .padding(.top, 28) // clearance under the hidden title bar
    }

    @ViewBuilder
    private var mainContent: some View {
        switch state.view {
        case .chat: ChatView()
        case .rubrics: RubricsView()
        case .activities: ActivitiesView()
        case .pogs: PogsView()
        case .integrations: IntegrationsView()
        }
    }
}
