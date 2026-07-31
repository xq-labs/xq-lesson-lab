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
                ForEach(SampleData.rubrics) { r in
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
                ForEach(SampleData.activities) { a in
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
                ForEach(SampleData.pogs) { p in
                    LibraryCard(title: p.title, sub: p.sub, meta: p.meta) {
                        state.openPreview(ArtifactRef(type: .pog, id: p.id))
                    }
                }
            }
        }
    }
}

struct IntegrationsView: View {
    @EnvironmentObject var state: AppState
    private var t: Theme { state.theme }

    var body: some View {
        LibraryPage(title: "Plugins",
                    subtitle: "Connected tools give the assistant context — rosters, schedules, files, and grades.") {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 280), spacing: 14)], spacing: 14) {
                ForEach(SampleData.integrationDefs, id: \.key) { def in
                    integrationCard(def)
                }
            }
        }
    }

    private func integrationCard(_ def: SampleData.IntegrationDef) -> some View {
        let on = state.connections[def.key] ?? false
        return VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 10) {
                Text(def.initial)
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(t.accent)
                    .frame(width: 32, height: 32)
                    .background(RoundedRectangle(cornerRadius: 9).fill(t.accentSoft))
                Text(def.name)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(t.text)
            }
            Text(def.desc)
                .font(.system(size: 12.5))
                .foregroundStyle(t.sub)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
            Spacer(minLength: 0)
            HStack(spacing: 8) {
                Circle()
                    .fill(on ? t.green : t.border)
                    .frame(width: 7, height: 7)
                Text(on ? "Connected" : "Not connected")
                    .font(.system(size: 12))
                    .foregroundStyle(t.sub)
                Spacer()
                Button {
                    state.connections[def.key] = !on
                } label: {
                    Text(on ? "Disconnect" : "Connect")
                        .font(.system(size: 12.5, weight: .semibold))
                        .foregroundStyle(on ? t.sub : .white)
                        .padding(.vertical, 5)
                        .padding(.horizontal, 12)
                        .background(
                            RoundedRectangle(cornerRadius: 8)
                                .fill(on ? .clear : t.accent)
                                .overlay(RoundedRectangle(cornerRadius: 8).stroke(on ? t.border : t.accent))
                        )
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
}
