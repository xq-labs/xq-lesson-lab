import SwiftUI

/// Shared scaffold for the Rubrics / Activities / PoGs / Plugins library pages.
struct LibraryPage<Content: View>: View {
    @EnvironmentObject var state: AppState
    var title: String
    var subtitle: String
    @ViewBuilder var content: Content

    private var t: Theme { state.theme }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                Text(title)
                    .font(.system(size: 20, weight: .bold))
                    .kerning(-0.2)
                Text(subtitle)
                    .foregroundStyle(t.sub)
                    .padding(.top, 4)
                    .padding(.bottom, 20)
                content
            }
            .frame(maxWidth: 960, alignment: .leading)
            .padding(.vertical, 24)
            .padding(.horizontal, 32)
            .frame(maxWidth: .infinity)
        }
    }
}

struct LibraryCard: View {
    @EnvironmentObject var state: AppState
    var title: String
    var sub: String
    var meta: String
    var action: () -> Void

    private var t: Theme { state.theme }

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 6) {
                Text(title)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(t.text)
                Text(sub)
                    .font(.system(size: 12.5))
                    .foregroundStyle(t.sub)
                    .fixedSize(horizontal: false, vertical: true)
                Text(meta)
                    .font(.system(size: 11.5))
                    .foregroundStyle(t.dim)
                    .padding(.top, 6)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .padding(16)
            .contentShape(RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
        .hoverHighlight(radius: 12, hover: t.hover, base: t.card)
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(t.border))
    }
}

struct RubricsView: View {
    @EnvironmentObject var state: AppState

    var body: some View {
        LibraryPage(title: "Rubrics",
                    subtitle: "Every rubric drafted in chat lands here. Open one to review it in the preview panel.") {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 250), spacing: 14)], spacing: 14) {
                ForEach(state.allRubrics) { r in
                    LibraryCard(title: r.title, sub: r.sub, meta: r.meta) {
                        state.openPreview(ArtifactRef(type: .rubric, id: r.id))
                    }
                }
            }
        }
    }
}

struct ActivitiesView: View {
    @EnvironmentObject var state: AppState

    var body: some View {
        LibraryPage(title: "Activities",
                    subtitle: "Reusable lessons, stations, and checks for understanding.") {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 250), spacing: 14)], spacing: 14) {
                ForEach(state.allActivities) { a in
                    LibraryCard(title: a.title, sub: a.desc, meta: a.meta) {
                        state.openPreview(ArtifactRef(type: .activity, id: a.id))
                    }
                }
            }
        }
    }
}

struct PogsView: View {
    @EnvironmentObject var state: AppState

    var body: some View {
        LibraryPage(title: "Portraits of a Graduate",
                    subtitle: "Competency portraits — the school template and per-student drafts.") {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 280), spacing: 14)], spacing: 14) {
                ForEach(state.allPogs) { p in
                    LibraryCard(title: p.title, sub: p.sub, meta: p.meta) {
                        state.openPreview(ArtifactRef(type: .pog, id: p.id))
                    }
                }
            }
        }
    }
}

struct QuizzesView: View {
    @EnvironmentObject var state: AppState
    private var t: Theme { state.theme }

    var body: some View {
        LibraryPage(title: "Quizzes",
                    subtitle: "Quizzes and exit tickets drafted in chat. Ask for one — \"make a 5-question exit ticket on…\"") {
            if state.allQuizzes.isEmpty {
                Text("Nothing here yet. Ask your assistant for a quiz or an exit ticket and it will land in this library.")
                    .font(.system(size: 13))
                    .foregroundStyle(t.dim)
                    .padding(.top, 8)
            } else {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 250), spacing: 14)], spacing: 14) {
                    ForEach(state.allQuizzes) { q in
                        LibraryCard(title: q.title, sub: q.sub, meta: q.meta) {
                            state.openPreview(ArtifactRef(type: .quiz, id: q.id))
                        }
                    }
                }
            }
        }
    }
}

struct IntegrationsView: View {
    @EnvironmentObject var state: AppState
    private var t: Theme { state.theme }

    private enum Tab { case plugins, skills }
    @State private var tab: Tab = .plugins

    var body: some View {
        // Same scaffold as LibraryPage, but the tab switcher sits above the
        // title so the title/subtitle change with it.
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                tabBar
                    .padding(.bottom, 18)
                Text(tab == .plugins ? "Plugins" : "Skills")
                    .font(.system(size: 20, weight: .bold))
                    .kerning(-0.2)
                Text(tab == .plugins
                     ? "Integrations that give the assistant context. On-device first — nothing leaves this Mac."
                     : "Extend the assistant with task-specific skills. Install the ones that fit your teaching.")
                    .foregroundStyle(t.sub)
                    .padding(.top, 4)
                    .padding(.bottom, 20)
                VStack(alignment: .leading, spacing: 18) {
                    switch tab {
                    case .plugins: pluginsTab
                    case .skills: skillsTab
                    }
                }
            }
            .frame(maxWidth: 960, alignment: .leading)
            .padding(.vertical, 24)
            .padding(.horizontal, 32)
            .frame(maxWidth: .infinity)
        }
    }

    private var tabBar: some View {
        HStack(spacing: 4) {
            tabButton("Plugins", .plugins)
            tabButton("Skills", .skills)
        }
        .padding(3)
        .background(RoundedRectangle(cornerRadius: 9).fill(t.side))
    }

    private func tabButton(_ label: String, _ value: Tab) -> some View {
        let selected = tab == value
        return Button {
            tab = value
        } label: {
            Text(label)
                .font(.system(size: 12.5, weight: .semibold))
                .foregroundStyle(selected ? t.text : t.sub)
                .padding(.vertical, 5)
                .padding(.horizontal, 14)
                .background(RoundedRectangle(cornerRadius: 7).fill(selected ? t.active : .clear))
                .contentShape(RoundedRectangle(cornerRadius: 7))
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var pluginsTab: some View {
        sectionHeader("AVAILABLE NOW")
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 280), spacing: 14)], spacing: 14) {
            rosterImportCard
            // Roster import is real; the calendar is a mock-connected demo
            // plugin, so it only stands alongside the rest of the sample data.
            if state.showsDemoPlugins {
                calendarCard
            }
        }
        sectionHeader("COMING SOON")
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 280), spacing: 14)], spacing: 14) {
            ForEach(SampleData.integrationDefs, id: \.key) { def in
                comingSoonCard(def)
            }
        }
    }

    @ViewBuilder
    private var skillsTab: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 280), spacing: 14)], spacing: 14) {
            ForEach(SampleData.skillDefs, id: \.key) { def in
                skillCard(def)
            }
        }
    }

    private func skillCard(_ def: SampleData.SkillDef) -> some View {
        let installed = state.installedSkills[def.key] ?? false
        return VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 10) {
                Image(systemName: def.icon)
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(installed ? t.accent : t.dim)
                    .frame(width: 32, height: 32)
                    .background(RoundedRectangle(cornerRadius: 9).fill(installed ? t.accentSoft : t.hover))
                Text(def.name)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(t.text)
                Spacer()
                if installed {
                    Image(systemName: "checkmark")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(t.green)
                }
            }
            Text(def.desc)
                .font(.system(size: 12.5))
                .foregroundStyle(t.sub)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
            Spacer(minLength: 0)
            HStack(spacing: 8) {
                if installed {
                    Circle().fill(t.green).frame(width: 7, height: 7)
                    Text("Installed")
                        .font(.system(size: 12))
                        .foregroundStyle(t.sub)
                }
                Spacer()
                Button {
                    state.installedSkills[def.key] = !installed
                } label: {
                    Text(installed ? "Remove" : "Install")
                        .font(.system(size: 12.5, weight: .semibold))
                        .foregroundStyle(installed ? t.sub : .white)
                        .padding(.vertical, 5)
                        .padding(.horizontal, 12)
                        .background(RoundedRectangle(cornerRadius: 8)
                            .fill(installed ? t.hover : t.accent))
                        .contentShape(RoundedRectangle(cornerRadius: 8))
                }
                .buttonStyle(.plain)
            }
            .padding(.top, 8)
        }
        .padding(16)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(t.card))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(t.border))
    }

    private func sectionHeader(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 11, weight: .bold))
            .kerning(0.66)
            .foregroundStyle(t.dim)
    }

    private var rosterImportCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 10) {
                Image(systemName: "square.and.arrow.down")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(t.accent)
                    .frame(width: 32, height: 32)
                    .background(RoundedRectangle(cornerRadius: 9).fill(t.accentSoft))
                Text("Roster import (CSV)")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(t.text)
            }
            Text("Paste student names or import a CSV export from any SIS — PowerSchool, Infinite Campus, Google Classroom. Everything stays on this Mac.")
                .font(.system(size: 12.5))
                .foregroundStyle(t.sub)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
            Spacer(minLength: 0)
            HStack(spacing: 8) {
                Circle().fill(t.green).frame(width: 7, height: 7)
                Text("Available")
                    .font(.system(size: 12))
                    .foregroundStyle(t.sub)
                Spacer()
                Button {
                    state.setView(.classroom)
                } label: {
                    Text("Open My Classroom")
                        .font(.system(size: 12.5, weight: .semibold))
                        .foregroundStyle(.white)
                        .padding(.vertical, 5)
                        .padding(.horizontal, 12)
                        .background(RoundedRectangle(cornerRadius: 8).fill(t.accent))
                        .contentShape(RoundedRectangle(cornerRadius: 8))
                }
                .buttonStyle(.plain)
            }
            .padding(.top, 8)
        }
        .padding(16)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(t.card))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(t.border))
    }

    /// Demo Google Calendar plugin — mock-connected for presentations.
    private var calendarCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 10) {
                Image(systemName: "calendar")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(t.accent)
                    .frame(width: 32, height: 32)
                    .background(RoundedRectangle(cornerRadius: 9).fill(t.accentSoft))
                Text("Google Calendar")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(t.text)
            }
            Text("Schedule-aware planning — lessons fit your real periods and meetings. Today's schedule is one click away in the header.")
                .font(.system(size: 12.5))
                .foregroundStyle(t.sub)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
            Spacer(minLength: 0)
            HStack(spacing: 8) {
                Circle().fill(t.green).frame(width: 7, height: 7)
                Text("Connected")
                    .font(.system(size: 12))
                    .foregroundStyle(t.sub)
                Spacer()
                Button {
                    state.scheduleOpen = true
                } label: {
                    Text("View today")
                        .font(.system(size: 12.5, weight: .semibold))
                        .foregroundStyle(.white)
                        .padding(.vertical, 5)
                        .padding(.horizontal, 12)
                        .background(RoundedRectangle(cornerRadius: 8).fill(t.accent))
                        .contentShape(RoundedRectangle(cornerRadius: 8))
                }
                .buttonStyle(.plain)
            }
            .padding(.top, 8)
        }
        .padding(16)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(t.card))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(t.border))
    }

    private func comingSoonCard(_ def: SampleData.IntegrationDef) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 10) {
                Text(def.initial)
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(t.dim)
                    .frame(width: 32, height: 32)
                    .background(RoundedRectangle(cornerRadius: 9).fill(t.hover))
                Text(def.name)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(t.sub)
                Spacer()
                Text("SOON")
                    .font(.system(size: 10, weight: .bold))
                    .kerning(0.5)
                    .foregroundStyle(t.dim)
                    .padding(.vertical, 3)
                    .padding(.horizontal, 8)
                    .background(Capsule().fill(t.hover))
            }
            Text(def.desc)
                .font(.system(size: 12.5))
                .foregroundStyle(t.dim)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
            Spacer(minLength: 0)
        }
        .padding(16)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(t.card).opacity(0.6))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(t.border))
    }
}
