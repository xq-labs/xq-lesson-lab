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

    /// `includeReview` is off by default because this is also the payload
    /// source for a frontier review — sending a model its own last critique
    /// back would be circular, and would double the bytes leaving the Mac.
    static func markdown(for ref: ArtifactRef, state: AppState,
                         includeReview: Bool = false) -> String? {
        let base: String?
        switch ref.type {
        case .rubric: base = state.rubric(id: ref.id).map(markdown(rubric:))
        case .activity: base = state.activity(id: ref.id).map(markdown(activity:))
        case .pog: base = state.pog(id: ref.id).map(markdown(pog:))
        case .quiz: base = state.quiz(id: ref.id).map(markdown(quiz:))
        case .email: base = state.email(id: ref.id).map(markdown(email:))
        }
        guard var md = base else { return nil }
        if includeReview, let review = state.latestReview(for: ref) {
            md += "\n" + markdown(review: review, classroom: state.classroom)
        }
        return md
    }

    /// The review as it appears under a copied document. Ends with the
    /// provenance line, in the same voice as "A draft judgment, made on this
    /// Mac." — where it ran, what it saw, and whose call it is.
    static func markdown(review: FrontierReview, classroom: Classroom) -> String {
        func shown(_ text: String) -> String { review.personalized(text, classroom: classroom) }

        var md = "\n## Second opinion\n\n"
        if !review.strengths.isEmpty {
            md += "**Strengths**\n\n"
            for line in review.strengths { md += "- \(shown(line))\n" }
            md += "\n"
        }
        if !review.suggestions.isEmpty {
            md += "**Suggestions**\n\n"
            for (i, s) in review.suggestions.enumerated() {
                let step = s.stepNumber.map { " _(step \($0))_" } ?? ""
                md += "\(i + 1). **\(shown(s.title))**\(step)  \n   \(shown(s.detail))\n"
            }
            md += "\n"
        }
        if !review.questions.isEmpty {
            md += "**Worth thinking about**\n\n"
            for q in review.questions { md += "- \(shown(q))\n" }
            md += "\n"
        }
        md += "_\(review.provenanceLine)_\n"
        return md
    }

    static func copyMarkdown(for ref: ArtifactRef, state: AppState) {
        guard let md = markdown(for: ref, state: state, includeReview: true) else { return }
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
        writePDF(view: PrintableArtifactView(ref: ref, state: state), to: url)
    }

    /// Ask where to save, then render any print view. The artifact path had
    /// this inline; a Skill Check isn't an artifact but wants the same page.
    static func savePDF<V: View>(view: V, title: String) {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.pdf]
        panel.nameFieldStringValue = title.replacingOccurrences(of: "/", with: "-") + ".pdf"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        writePDF(view: view, to: url)
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    /// US-Letter width, content-sized single page.
    static func writePDF<V: View>(view: V, to url: URL) {
        let renderer = ImageRenderer(content: view.frame(width: 612))
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

    // MARK: - Skill checks

    static func markdown(evaluation e: SkillEvaluation, framework: XQFramework?) -> String {
        var out = "# \(e.workLabel)\n\n"
        out += "**\(e.competencyName) — \(e.skillName)**\n\n"
        out += "## \(e.levelLabel)\n\n\(e.levelDescriptor)\n\n"
        if e.teacherLevel != nil {
            out += "_Placed here by the teacher; the check suggested \(e.levelLabel)._\n\n"
        }
        if !e.evidence.isEmpty {
            out += "## Why\n\n"
            for quote in e.evidence { out += "> \(quote)\n\n" }
        }
        if let next = e.nextStep { out += "## Next step\n\n\(next)\n\n" }
        if e.hasMixedEvidence { out += "_The rungs disagreed with each other — this placement is marginal._\n\n" }
        if e.isOffTopic { out += "_This work may not be about this skill._\n\n" }
        out += "---\n\n\(framework?.attribution ?? "XQ Competencies · © XQ Institute · CC BY 4.0")\n"
        return out
    }
}

/// Print-styled rendition of a saved Skill Check.
struct PrintableEvaluationView: View {
    var evaluation: SkillEvaluation
    var framework: XQFramework?

    private let ink = Color.black
    private let faint = Color(white: 0.35)

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(evaluation.workLabel)
                .font(.system(size: 20, weight: .bold))
                .foregroundStyle(ink)
            Text("\(evaluation.competencyName) — \(evaluation.skillName)")
                .font(.system(size: 12))
                .foregroundStyle(faint)

            Text(framework?.levelLabel(evaluation.effectiveLevel) ?? evaluation.levelLabel)
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(ink)
                .padding(.top, 6)
            Text(evaluation.levelDescriptor)
                .font(.system(size: 12))
                .foregroundStyle(ink)

            if !evaluation.evidence.isEmpty {
                Text("Why")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(ink)
                    .padding(.top, 6)
                ForEach(Array(evaluation.evidence.enumerated()), id: \.offset) { _, quote in
                    Text("\u{201C}\(quote)\u{201D}")
                        .font(.system(size: 12))
                        .foregroundStyle(ink)
                }
            }

            if let next = evaluation.nextStep {
                Text("Next step")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(ink)
                    .padding(.top, 6)
                Text(next)
                    .font(.system(size: 12))
                    .foregroundStyle(ink)
            }

            if !evaluation.isConfident {
                Text(evaluation.isOffTopic
                     ? "This work may not be about this skill."
                     : "The rungs disagreed with each other — this placement is marginal.")
                    .font(.system(size: 10))
                    .foregroundStyle(faint)
                    .padding(.top, 6)
            }

            Text("A draft judgment, made on this Mac. \(framework?.attribution ?? "")")
                .font(.system(size: 9))
                .foregroundStyle(Color(white: 0.6))
                .padding(.top, 10)
        }
        .padding(40)
        .frame(width: 612, alignment: .leading)
        .background(Color.white)
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

            if let review = state.latestReview(for: ref) {
                printedReview(review)
            }

            // The document itself carries no provenance mark, because the
            // document never left in modified form. The review does. A teacher
            // who ignores the review and prints the plan has printed something
            // that never went anywhere, and the paper shouldn't claim otherwise.
            Text(state.latestReview(for: ref).map { review in
                "Made with \(AppInfo.productName). The second opinion above came from "
                    + "\(review.modelDisplayName) on \(review.dateLine) — the document text "
                    + "was sent over the internet for that review. Rosters and student "
                    + "notes were not."
            } ?? "Made with \(AppInfo.productName)")
                .font(.system(size: 9))
                .foregroundStyle(Color(white: 0.6))
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 10)
        }
        .padding(36)
        .frame(width: 612, alignment: .leading)
        .background(Color.white)
    }

    @ViewBuilder
    private func printedReview(_ review: FrontierReview) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Rectangle().fill(Color(white: 0.85)).frame(height: 1)
            Text("Second opinion — \(review.modelDisplayName), \(review.dateLine)")
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(ink)

            if !review.strengths.isEmpty {
                Text("Strengths").font(.system(size: 10, weight: .semibold)).foregroundStyle(faint)
                ForEach(review.strengths, id: \.self) { line in
                    Text("• \(review.personalized(line, classroom: state.classroom))")
                        .font(.system(size: 10.5)).foregroundStyle(ink)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            if !review.suggestions.isEmpty {
                Text("Suggestions").font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(faint).padding(.top, 4)
                ForEach(Array(review.suggestions.enumerated()), id: \.offset) { i, s in
                    VStack(alignment: .leading, spacing: 2) {
                        Text("\(i + 1). \(review.personalized(s.title, classroom: state.classroom))")
                            .font(.system(size: 10.5, weight: .semibold)).foregroundStyle(ink)
                        Text(review.personalized(s.detail, classroom: state.classroom))
                            .font(.system(size: 10.5)).foregroundStyle(faint)
                    }
                    .fixedSize(horizontal: false, vertical: true)
                }
            }
            if !review.questions.isEmpty {
                Text("Worth thinking about").font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(faint).padding(.top, 4)
                ForEach(review.questions, id: \.self) { q in
                    Text("• \(review.personalized(q, classroom: state.classroom))")
                        .font(.system(size: 10.5)).foregroundStyle(faint)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .padding(.top, 12)
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
