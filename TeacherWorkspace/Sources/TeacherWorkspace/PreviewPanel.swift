import SwiftUI

struct PreviewPanel: View {
    @EnvironmentObject var state: AppState
    var ref: ArtifactRef

    private var t: Theme { state.theme }

    private var title: String { state.artifact(for: ref)?.title ?? "" }
    private var meta: String { state.artifact(for: ref)?.meta ?? "" }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            panelBar
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 15, weight: .bold))
                Text(meta)
                    .font(.system(size: 11.5))
                    .foregroundStyle(t.dim)
            }
            .padding(.top, 14)
            .padding(.horizontal, 20)
            ScrollView {
                Group {
                    switch ref.type {
                    case .rubric:
                        if let r = SampleData.rubrics.first(where: { $0.id == ref.id }) {
                            rubricBody(r)
                        }
                    case .activity:
                        if let a = SampleData.activities.first(where: { $0.id == ref.id }) {
                            activityBody(a)
                        }
                    case .pog:
                        if let p = SampleData.pogs.first(where: { $0.id == ref.id }) {
                            pogBody(p)
                        }
                    }
                }
                .padding(.vertical, 16)
                .padding(.horizontal, 20)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .frame(width: state.previewWide ? 660 : 430)
        .background(t.bg)
        .overlay(alignment: .leading) {
            Rectangle().fill(t.border).frame(width: 1)
        }
    }

    private var panelBar: some View {
        HStack(spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: "doc.text")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(t.dim)
                Text(title)
                    .font(.system(size: 12.5, weight: .semibold))
                    .foregroundStyle(t.text)
                    .lineLimit(1)
                    .truncationMode(.tail)
                Spacer(minLength: 0)
                Button {
                    state.closePreview()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(t.dim)
                        .frame(width: 18, height: 18)
                }
                .buttonStyle(.plain)
                .hoverHighlight(radius: 5, hover: t.hover)
                .help("Close")
            }
            .padding(.vertical, 6)
            .padding(.horizontal, 10)
            .background(RoundedRectangle(cornerRadius: 9).fill(t.card))
            Button {
                state.previewWide.toggle()
            } label: {
                Image(systemName: "arrow.up.left.and.arrow.down.right")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(t.sub)
                    .frame(width: 28, height: 28)
            }
            .buttonStyle(.plain)
            .hoverHighlight(radius: 7, hover: t.hover)
            .help("Expand")
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 10)
        .overlay(alignment: .bottom) {
            Rectangle().fill(t.border).frame(height: 1)
        }
    }

    // MARK: - Rubric

    private func rubricBody(_ rubric: Rubric) -> some View {
        VStack(alignment: .leading, spacing: 18) {
            ForEach(rubric.criteria, id: \.name) { crit in
                VStack(alignment: .leading, spacing: 0) {
                    Text(crit.name)
                        .font(.system(size: 13, weight: .bold))
                        .padding(.vertical, 8)
                        .padding(.horizontal, 12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(t.card)
                    ForEach(Array(crit.cells.enumerated()), id: \.offset) { i, cell in
                        HStack(alignment: .top, spacing: 10) {
                            Text(SampleData.levels4[i])
                                .font(.system(size: 11.5, weight: .bold))
                                .foregroundStyle(i == 2 ? t.accent : t.dim)
                                .frame(width: 82, alignment: .leading)
                            Text(cell)
                                .font(.system(size: 12.5))
                                .foregroundStyle(t.sub)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .padding(.vertical, 8)
                        .padding(.horizontal, 12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .overlay(alignment: .top) {
                            Rectangle().fill(t.border).frame(height: 1)
                        }
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).stroke(t.border))
            }
        }
    }

    // MARK: - Activity

    private func activityBody(_ activity: Activity) -> some View {
        let parts = activity.meta.components(separatedBy: " · ")
        return VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 8) {
                ForEach(parts, id: \.self) { part in
                    Text(part)
                        .font(.system(size: 11.5, weight: .semibold))
                        .foregroundStyle(t.sub)
                        .padding(.vertical, 3)
                        .padding(.horizontal, 10)
                        .background(Capsule().fill(t.card))
                }
            }
            Text(activity.desc)
                .font(.system(size: 13.5))
                .foregroundStyle(t.sub)
                .fixedSize(horizontal: false, vertical: true)
            Text("STEPS")
                .font(.system(size: 12, weight: .bold))
                .kerning(0.6)
                .foregroundStyle(t.dim)
            VStack(alignment: .leading, spacing: 10) {
                ForEach(Array(activity.steps.enumerated()), id: \.offset) { i, step in
                    HStack(alignment: .top, spacing: 10) {
                        Text("\(i + 1)")
                            .font(.system(size: 11.5, weight: .bold))
                            .foregroundStyle(t.accent)
                            .frame(width: 22, height: 22)
                            .background(Circle().fill(t.accentSoft))
                        Text(step)
                            .font(.system(size: 13))
                            .foregroundStyle(t.sub)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.top, 1)
                    }
                }
            }
        }
    }

    // MARK: - PoG

    private func pogBody(_ pog: Pog) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Click a dot to set the current level for each competency.")
                .font(.system(size: 12.5))
                .foregroundStyle(t.sub)
            ForEach(Array(pog.comps.enumerated()), id: \.offset) { ci, comp in
                let key = "\(pog.id)-\(ci)"
                let level = state.pogLevels[key] ?? comp.level
                VStack(alignment: .leading, spacing: 6) {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(comp.name)
                            .font(.system(size: 13.5, weight: .bold))
                            .foregroundStyle(t.text)
                        Spacer()
                        Text(SampleData.pogLabels[level - 1])
                            .font(.system(size: 11.5, weight: .semibold))
                            .foregroundStyle(t.accent)
                    }
                    Text(comp.desc)
                        .font(.system(size: 12.5))
                        .foregroundStyle(t.sub)
                        .fixedSize(horizontal: false, vertical: true)
                    HStack(spacing: 7) {
                        ForEach(1...5, id: \.self) { n in
                            Button {
                                state.pogLevels[key] = n
                            } label: {
                                Circle()
                                    .fill(n <= level ? t.accent : t.card)
                                    .overlay(Circle().stroke(n <= level ? t.accent : t.border, lineWidth: 1.5))
                                    .frame(width: 18, height: 18)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.top, 4)
                }
                .padding(.vertical, 12)
                .padding(.horizontal, 14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).stroke(t.border))
            }
        }
    }
}
