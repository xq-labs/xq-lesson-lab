import SwiftUI
import AppKit
import UniformTypeIdentifiers

/// Markdown + PDF export for library artifacts.
@MainActor
enum ArtifactExport {

    // MARK: - Markdown

    static func markdown(rubric: Rubric) -> String {
        var md = "# \(rubric.title)\n\n\(rubric.sub)\n"
        for crit in rubric.criteria {
            md += "\n## \(crit.name)\n\n"
            md += "| Level | Description |\n|---|---|\n"
            for (i, cell) in crit.cells.enumerated() {
                let label = i < SampleData.levels4.count ? SampleData.levels4[i] : "Level \(i + 1)"
                md += "| **\(label)** | \(cell.replacingOccurrences(of: "|", with: "\\|")) |\n"
            }
        }
        return md
    }

    static func markdown(activity: Activity) -> String {
        var md = "# \(activity.title)\n\n_\(activity.meta)_\n\n\(activity.desc)\n\n## Steps\n\n"
        for (i, step) in activity.steps.enumerated() {
            md += "\(i + 1). \(step)\n"
        }
        return md
    }

    static func markdown(pog: Pog) -> String {
        var md = "# \(pog.title)\n\n\(pog.sub)\n\n"
        for comp in pog.comps {
            let label = SampleData.pogLabels[min(4, max(0, comp.level - 1))]
            md += "## \(comp.name) — \(label) (\(comp.level)/5)\n\n\(comp.desc)\n\n"
        }
        return md
    }

    static func markdown(quiz: Quiz) -> String {
        var md = "# \(quiz.title)\n\n\(quiz.sub)\n\n"
        for (i, q) in quiz.questions.enumerated() {
            md += "**\(i + 1). \(q.prompt)**\n\n"
            for (ci, choice) in q.choices.enumerated() {
                let letter = String(UnicodeScalar(65 + ci % 26)!)
                md += "- \(letter). \(choice)\n"
            }
            if !q.answer.isEmpty { md += "\n_Answer: \(q.answer)_\n" }
            md += "\n"
        }
        return md
    }

    static func markdown(email: EmailDraft) -> String {
        "Subject: \(email.title)\n\n\(email.body)\n"
    }

    static func markdown(for ref: ArtifactRef, state: AppState) -> String? {
        switch ref.type {
        case .rubric: return state.rubric(id: ref.id).map(markdown(rubric:))
        case .activity: return state.activity(id: ref.id).map(markdown(activity:))
        case .pog: return state.pog(id: ref.id).map(markdown(pog:))
        case .quiz: return state.quiz(id: ref.id).map(markdown(quiz:))
        case .email: return state.email(id: ref.id).map(markdown(email:))
        }
    }

    static func copyMarkdown(for ref: ArtifactRef, state: AppState) {
        guard let md = markdown(for: ref, state: state) else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(md, forType: .string)
    }

    // MARK: - PDF

    /// Renders the artifact as a single content-sized PDF page (US-Letter
    /// width) and asks where to save it.
    static func savePDF(for ref: ArtifactRef, state: AppState) {
        guard let title = state.artifact(for: ref)?.title else { return }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.pdf]
        panel.nameFieldStringValue = title.replacingOccurrences(of: "/", with: "-") + ".pdf"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        writePDF(for: ref, state: state, to: url)
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    /// Split from savePDF so automated tests can render without a dialog.
    static func writePDF(for ref: ArtifactRef, state: AppState, to url: URL) {
        let content = PrintableArtifactView(ref: ref, state: state)
            .frame(width: 612)
        let renderer = ImageRenderer(content: content)
        renderer.proposedSize = ProposedViewSize(width: 612, height: nil)
        renderer.render { size, renderIn in
            var mediaBox = CGRect(origin: .zero, size: size)
            guard let ctx = CGContext(url as CFURL, mediaBox: &mediaBox, nil) else { return }
            ctx.beginPDFPage(nil)
            renderIn(ctx)
            ctx.endPDFPage()
            ctx.closePDF()
        }
    }
}

/// Print-styled (black on white) rendition of an artifact.
struct PrintableArtifactView: View {
    var ref: ArtifactRef
    var state: AppState

    private let ink = Color.black
    private let faint = Color(white: 0.35)

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            switch ref.type {
            case .rubric:
                if let r = state.rubric(id: ref.id) { rubricBody(r) }
            case .activity:
                if let a = state.activity(id: ref.id) { activityBody(a) }
            case .pog:
                if let p = state.pog(id: ref.id) { pogBody(p) }
            case .quiz:
                if let q = state.quiz(id: ref.id) { quizBody(q) }
            case .email:
                if let e = state.email(id: ref.id) { emailBody(e) }
            }
            Text("Made with \(AppInfo.productName)")
                .font(.system(size: 9))
                .foregroundStyle(Color(white: 0.6))
                .padding(.top, 10)
        }
        .padding(36)
        .frame(width: 612, alignment: .leading)
        .background(Color.white)
    }

    private func header(_ title: String, _ subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title).font(.system(size: 19, weight: .bold)).foregroundStyle(ink)
            if !subtitle.isEmpty {
                Text(subtitle).font(.system(size: 11)).foregroundStyle(faint)
            }
        }
    }

    private func rubricBody(_ r: Rubric) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            header(r.title, r.sub)
            ForEach(r.criteria, id: \.name) { crit in
                VStack(alignment: .leading, spacing: 0) {
                    Text(crit.name)
                        .font(.system(size: 12, weight: .bold)).foregroundStyle(ink)
                        .padding(6)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color(white: 0.93))
                    ForEach(Array(crit.cells.enumerated()), id: \.offset) { i, cell in
                        HStack(alignment: .top, spacing: 8) {
                            Text(i < SampleData.levels4.count ? SampleData.levels4[i] : "L\(i + 1)")
                                .font(.system(size: 10, weight: .bold)).foregroundStyle(faint)
                                .frame(width: 70, alignment: .leading)
                            Text(cell)
                                .font(.system(size: 10.5)).foregroundStyle(ink)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .padding(6)
                        .overlay(alignment: .top) { Color(white: 0.85).frame(height: 0.5) }
                    }
                }
                .overlay(RoundedRectangle(cornerRadius: 4).stroke(Color(white: 0.75), lineWidth: 0.7))
            }
        }
    }

    private func activityBody(_ a: Activity) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            header(a.title, a.meta)
            Text(a.desc).font(.system(size: 11)).foregroundStyle(ink)
                .fixedSize(horizontal: false, vertical: true)
            Text("STEPS").font(.system(size: 10, weight: .bold)).foregroundStyle(faint)
            VStack(alignment: .leading, spacing: 7) {
                ForEach(Array(a.steps.enumerated()), id: \.offset) { i, step in
                    HStack(alignment: .top, spacing: 8) {
                        Text("\(i + 1).").font(.system(size: 11, weight: .bold)).foregroundStyle(ink)
                        Text(step).font(.system(size: 11)).foregroundStyle(ink)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
    }

    private func quizBody(_ q: Quiz) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            header(q.title, q.sub)
            ForEach(Array(q.questions.enumerated()), id: \.offset) { i, question in
                VStack(alignment: .leading, spacing: 4) {
                    Text("\(i + 1). \(question.prompt)")
                        .font(.system(size: 11.5, weight: .bold)).foregroundStyle(ink)
                        .fixedSize(horizontal: false, vertical: true)
                    ForEach(Array(question.choices.enumerated()), id: \.offset) { ci, choice in
                        Text("\(String(UnicodeScalar(65 + ci % 26)!)). \(choice)")
                            .font(.system(size: 10.5)).foregroundStyle(ink)
                            .padding(.leading, 14)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    if question.choices.isEmpty {
                        Text("Answer: ______________________________")
                            .font(.system(size: 10.5)).foregroundStyle(faint)
                            .padding(.leading, 14)
                    }
                }
            }
        }
    }

    private func emailBody(_ e: EmailDraft) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            header("Subject: \(e.title)", e.sub)
            Text(e.body)
                .font(.system(size: 11)).foregroundStyle(ink)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func pogBody(_ p: Pog) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            header(p.title, p.sub)
            ForEach(Array(p.comps.enumerated()), id: \.offset) { _, comp in
                VStack(alignment: .leading, spacing: 3) {
                    HStack {
                        Text(comp.name).font(.system(size: 12, weight: .bold)).foregroundStyle(ink)
                        Spacer()
                        Text("\(SampleData.pogLabels[min(4, max(0, comp.level - 1))]) · \(comp.level)/5")
                            .font(.system(size: 10, weight: .semibold)).foregroundStyle(faint)
                    }
                    Text(comp.desc).font(.system(size: 10.5)).foregroundStyle(ink)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(8)
                .overlay(RoundedRectangle(cornerRadius: 4).stroke(Color(white: 0.75), lineWidth: 0.7))
            }
        }
    }
}
