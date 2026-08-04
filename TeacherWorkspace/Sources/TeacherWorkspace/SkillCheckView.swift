import SwiftUI
import UniformTypeIdentifiers

/// Place a piece of student work on an XQ component skill's progression.
///
/// The level is presented as a suggestion sitting next to the descriptor it
/// was matched against and the student's own sentences — a wrong level beside
/// the real evidence is something a teacher can argue with, while a wrong
/// level on its own is just an institution's name on a bad guess.
struct SkillCheckView: View {
    @EnvironmentObject var state: AppState
    @StateObject private var frameworks = FrameworkStore.shared
    @StateObject private var runner = EvaluationRunner()

    @State private var mode: Mode = .list
    @State private var workText = ""
    @State private var workLabel = ""
    @State private var sourceName: String?
    @State private var selectedSkillId: String?
    @State private var skillQuery = ""
    @State private var intakeProblem: String?
    @State private var isTargetedForDrop = false
    /// A saved check being read back, as opposed to one just produced.
    @State private var openedEvaluation: SkillEvaluation?

    private enum Mode { case list, run }

    private var t: Theme { state.theme }
    private var framework: XQFramework? { frameworks.framework }

    var body: some View {
        Group {
            switch mode {
            case .list: listMode
            case .run: runMode
            }
        }
        .onAppear {
            frameworks.loadIfNeeded()
            seedForSnapshot()
        }
        // The framework parses off the main thread, so a snapshot seeded at
        // onAppear has no skills to resolve against yet.
        .onChange(of: frameworks.phase) { _, _ in seedForSnapshot() }
    }

    // MARK: - Saved checks

    private var listMode: some View {
        LibraryPage(title: "Skill Check",
                    subtitle: "Place a piece of student work on an XQ competency progression — with the sentences that put it there.") {
            VStack(alignment: .leading, spacing: 16) {
                Button {
                    startNewCheck()
                } label: {
                    Label("New skill check", systemImage: "plus")
                        .font(.system(size: 13, weight: .semibold))
                        .padding(.vertical, 8)
                        .padding(.horizontal, 14)
                        .contentShape(RoundedRectangle(cornerRadius: 9))
                }
                .buttonStyle(.plain)
                .foregroundStyle(t.accent)
                .hoverHighlight(radius: 9, hover: t.hover, base: t.accentSoft)
                .disabled(frameworks.phase != .ready)

                if case .failed(let message) = frameworks.phase {
                    noticeRow(message, tint: t.red)
                }

                if state.skillEvaluations.isEmpty {
                    Text("Nothing here yet. Start a check, paste or open a piece of student work, and pick the component skill you want it read against.")
                        .font(.system(size: 13))
                        .foregroundStyle(t.dim)
                } else {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 260), spacing: 14)], spacing: 14) {
                        ForEach(state.skillEvaluations) { evaluation in
                            LibraryCard(title: evaluation.title,
                                        sub: evaluation.sub,
                                        meta: evaluation.meta) {
                                openedEvaluation = evaluation
                                mode = .run
                            }
                                .overlay(alignment: .topTrailing) {
                                    if !evaluation.isConfident {
                                        Image(systemName: "exclamationmark.triangle.fill")
                                            .font(.system(size: 10))
                                            .foregroundStyle(t.red)
                                            .padding(10)
                                    }
                                }
                        }
                    }
                }

                if let framework {
                    Text(framework.attribution)
                        .font(.system(size: 11))
                        .foregroundStyle(t.dim)
                        .padding(.top, 4)
                }
            }
        }
    }

    // MARK: - Running a check

    private var runMode: some View {
        LibraryPage(title: "Skill Check",
                    subtitle: "Paste the work, choose the skill, and read the result against the student's own sentences.") {
            VStack(alignment: .leading, spacing: 18) {
                HStack {
                    Button {
                        runner.reset()
                        openedEvaluation = nil
                        mode = .list
                    } label: {
                        Label("Saved checks", systemImage: "chevron.left")
                            .font(.system(size: 12.5, weight: .medium))
                            .foregroundStyle(t.sub)
                    }
                    .buttonStyle(.plain)
                    Spacer()
                }

                if let result = openedEvaluation ?? runner.result {
                    resultCard(result)
                } else {
                    workSection
                    skillSection
                    runSection
                }
            }
        }
    }

    private var workSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionTitle("The work")
            TextField("What was the assignment? (describe the task, not the student)", text: $workLabel)
                .textFieldStyle(.plain)
                .font(.system(size: 13))
                .padding(.vertical, 7)
                .padding(.horizontal, 10)
                .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(t.input))
                .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).stroke(t.border))

            if namesAStudent {
                noticeRow("That label looks like a student's name. The check isn't filed against a student — describing the assignment keeps it that way.",
                          tint: t.sub)
            }

            ZStack(alignment: .topLeading) {
                TextEditor(text: $workText)
                    .font(.system(size: 13))
                    .scrollContentBackground(.hidden)
                    .padding(8)
                    .frame(minHeight: 200)
                if workText.isEmpty {
                    Text("Paste the student's work here, or drop a file on this box.")
                        .font(.system(size: 13))
                        .foregroundStyle(t.dim)
                        .padding(.horizontal, 13)
                        .padding(.vertical, 16)
                        .allowsHitTesting(false)
                }
            }
            .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(t.input))
            .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(isTargetedForDrop ? t.accent : t.border, lineWidth: isTargetedForDrop ? 2 : 1))
            .dropDestination(for: URL.self) { urls, _ in
                guard let url = urls.first else { return false }
                load(url)
                return true
            } isTargeted: { isTargetedForDrop = $0 }

            HStack(spacing: 10) {
                Button("Open a file…") { openFile() }
                    .buttonStyle(.plain)
                    .font(.system(size: 12.5, weight: .medium))
                    .foregroundStyle(t.accent)
                if let sourceName {
                    Text("from \(sourceName)")
                        .font(.system(size: 11.5))
                        .foregroundStyle(t.dim)
                }
                Spacer()
                Text(characterCount)
                    .font(.system(size: 11.5))
                    .foregroundStyle(workText.count > WorkDocument.maxCharacters ? t.red : t.dim)
            }

            if workText.count > WorkDocument.maxCharacters {
                noticeRow("Only the first \(WorkDocument.maxCharacters) characters will be read.", tint: t.red)
            }
            if let intakeProblem {
                noticeRow(intakeProblem, tint: t.red)
            }
        }
    }

    private var skillSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionTitle("The skill")

            if !suggestions.isEmpty, selectedSkillId == nil {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Skills whose wording overlaps this work — these are a starting point, not a judgment.")
                        .font(.system(size: 11.5))
                        .foregroundStyle(t.dim)
                    FlowRow(spacing: 6) {
                        ForEach(suggestions) { skill in
                            Button {
                                selectedSkillId = skill.id
                            } label: {
                                Text(skill.name)
                                    .font(.system(size: 11.5, weight: .semibold))
                                    .foregroundStyle(t.accent)
                                    .padding(.vertical, 4)
                                    .padding(.horizontal, 9)
                                    .background(Capsule().fill(t.accentSoft))
                            }
                            .buttonStyle(.plain)
                            .help("\(skill.competencyName) — \(skill.detail)")
                        }
                    }
                }
                .padding(.bottom, 4)
            }

            if let skill = selectedSkill {
                selectedSkillCard(skill)
            } else {
                skillPicker
            }
        }
    }

    private func selectedSkillCard(_ skill: ComponentSkill) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(skill.competencyName)
                    .font(.system(size: 11.5, weight: .semibold))
                    .foregroundStyle(t.dim)
                Spacer()
                Button("Change") { selectedSkillId = nil }
                    .buttonStyle(.plain)
                    .font(.system(size: 11.5, weight: .medium))
                    .foregroundStyle(t.accent)
            }
            Text(skill.name)
                .font(.system(size: 14, weight: .semibold))
            Text(skill.detail)
                .font(.system(size: 12.5))
                .foregroundStyle(t.sub)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(t.card))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(t.border))
    }

    private var skillPicker: some View {
        VStack(alignment: .leading, spacing: 8) {
            TextField("Search 115 component skills…", text: $skillQuery)
                .textFieldStyle(.plain)
                .font(.system(size: 13))
                .padding(.vertical, 7)
                .padding(.horizontal, 10)
                .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(t.input))
                .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).stroke(t.border))

            if !recentSkills.isEmpty, skillQuery.isEmpty {
                Text("RECENT")
                    .font(.system(size: 10, weight: .bold))
                    .kerning(0.6)
                    .foregroundStyle(t.dim)
                ForEach(recentSkills) { skill in skillRow(skill) }
                Divider().padding(.vertical, 4)
            }

            ScrollView {
                VStack(alignment: .leading, spacing: 1) {
                    ForEach(frameworks.search(skillQuery)) { skill in skillRow(skill) }
                }
            }
            .frame(maxHeight: 260)
        }
    }

    private func skillRow(_ skill: ComponentSkill) -> some View {
        Button {
            selectedSkillId = skill.id
            skillQuery = ""
        } label: {
            VStack(alignment: .leading, spacing: 2) {
                Text(skill.name)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(t.text)
                Text(skill.competencyName)
                    .font(.system(size: 11.5))
                    .foregroundStyle(t.dim)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 6)
            .padding(.horizontal, 10)
            .contentShape(RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
        .hoverHighlight(radius: 8, hover: t.hover)
    }

    private var runSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                Button {
                    start()
                } label: {
                    Text(runner.phase.isRunning ? "Reading…" : "Run skill check")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(canRun ? t.sendFg : t.dim)
                        .padding(.vertical, 9)
                        .padding(.horizontal, 18)
                        .background(Capsule().fill(canRun ? t.sendBg : t.hover))
                }
                .buttonStyle(.plain)
                .disabled(!canRun)

                if runner.phase.isRunning {
                    Button("Cancel") { runner.cancel() }
                        .buttonStyle(.plain)
                        .font(.system(size: 12.5, weight: .medium))
                        .foregroundStyle(t.sub)
                }

                if case .running(let stage) = runner.phase {
                    HStack(spacing: 6) {
                        ProgressView().controlSize(.small)
                        Text(stage)
                            .font(.system(size: 12))
                            .foregroundStyle(t.sub)
                    }
                }
            }

            if state.isStreaming {
                noticeRow("The assistant is writing a reply. The model runs one task at a time, so this waits until it's done.", tint: t.sub)
            }
            if case .failed(let message) = runner.phase {
                noticeRow(message, tint: t.red)
            }
            if case .cancelled = runner.phase {
                noticeRow("Stopped.", tint: t.sub)
            }
        }
    }

    // MARK: - Result

    private func resultCard(_ result: SkillEvaluation) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text(result.competencyName)
                    .font(.system(size: 11.5, weight: .semibold))
                    .foregroundStyle(t.dim)
                Text(result.skillName)
                    .font(.system(size: 17, weight: .bold))
            }

            if !result.isConfident {
                noticeRow(result.isOffTopic
                          ? "This work may not be about this skill at all — read the rungs below before trusting the level."
                          : "The rungs disagree with each other, which usually means the placement is marginal.",
                          tint: t.red)
            }

            progressionLadder(result)

            if !result.evidence.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    sectionTitle("Why")
                    ForEach(Array(result.evidence.enumerated()), id: \.offset) { _, sentence in
                        Text("“\(sentence)”")
                            .font(.system(size: 13))
                            .foregroundStyle(t.text)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(10)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(t.bubble))
                    }
                    Text("Quoted from the work itself — the check points at sentences, it doesn't write them.")
                        .font(.system(size: 11))
                        .foregroundStyle(t.dim)
                }
            }

            if let nextStep = result.nextStep {
                VStack(alignment: .leading, spacing: 6) {
                    sectionTitle("Next step")
                    Text(nextStep)
                        .font(.system(size: 13))
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            HStack(spacing: 12) {
                if openedEvaluation == nil {
                    Button {
                        save(result)
                    } label: {
                        Text("Save this check")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(t.sendFg)
                            .padding(.vertical, 9)
                            .padding(.horizontal, 18)
                            .background(Capsule().fill(t.sendBg))
                    }
                    .buttonStyle(.plain)

                    Button("Discard") { runner.reset() }
                        .buttonStyle(.plain)
                        .font(.system(size: 12.5, weight: .medium))
                        .foregroundStyle(t.sub)
                }
                Button("Copy as Markdown") {
                    let md = ArtifactExport.markdown(evaluation: result, framework: framework)
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(md, forType: .string)
                }
                .buttonStyle(.plain)
                .font(.system(size: 12.5, weight: .medium))
                .foregroundStyle(t.accent)

                Button("Save as PDF…") {
                    ArtifactExport.savePDF(
                        view: PrintableEvaluationView(evaluation: result, framework: framework),
                        title: result.workLabel)
                }
                .buttonStyle(.plain)
                .font(.system(size: 12.5, weight: .medium))
                .foregroundStyle(t.accent)
                Spacer()
            }

            Text("A draft judgment — you decide. \(framework?.attribution ?? "")")
                .font(.system(size: 11))
                .foregroundStyle(t.dim)
        }
    }

    /// The four rungs, with the placed one lit. Reads `levelLabel(_:)` rather
    /// than indexing a labels array, so a framework with a different number of
    /// rungs renders instead of trapping.
    private func progressionLadder(_ result: SkillEvaluation) -> some View {
        let skill = framework?.skill(id: result.skillId)
        return VStack(alignment: .leading, spacing: 6) {
            sectionTitle("Where this lands")
            ForEach(skill?.progression.sorted { $0.ordinal < $1.ordinal } ?? [], id: \.ordinal) { rung in
                let isPlaced = rung.ordinal == result.effectiveLevel
                HStack(alignment: .top, spacing: 10) {
                    Text("\(rung.ordinal)")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(isPlaced ? t.sendFg : t.dim)
                        .frame(width: 20, height: 20)
                        .background(Circle().fill(isPlaced ? t.accent : t.hover))
                    VStack(alignment: .leading, spacing: 2) {
                        Text(framework?.levelLabel(rung.ordinal) ?? "Level \(rung.ordinal)")
                            .font(.system(size: 12.5, weight: isPlaced ? .bold : .medium))
                            .foregroundStyle(isPlaced ? t.text : t.sub)
                        Text(rung.descriptor)
                            .font(.system(size: 12))
                            .foregroundStyle(isPlaced ? t.sub : t.dim)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 0)
                    Button {
                        setTeacherLevel(rung.ordinal)
                    } label: {
                        Text(isPlaced ? "Placed" : "Move here")
                            .font(.system(size: 10.5, weight: .semibold))
                            .foregroundStyle(isPlaced ? t.dim : t.accent)
                    }
                    .buttonStyle(.plain)
                    .opacity(isPlaced ? 0.6 : 1)
                }
                .padding(10)
                .background(RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(isPlaced ? t.accentSoft : Color.clear))
            }
            if result.teacherLevel != nil {
                Text("You moved this from \(result.levelLabel).")
                    .font(.system(size: 11))
                    .foregroundStyle(t.dim)
            }
        }
    }

    // MARK: - Bits

    private func sectionTitle(_ text: String) -> some View {
        Text(text.uppercased())
            .font(.system(size: 10, weight: .bold))
            .kerning(0.6)
            .foregroundStyle(t.dim)
    }

    private func noticeRow(_ text: String, tint: Color) -> some View {
        HStack(alignment: .top, spacing: 6) {
            Image(systemName: "info.circle")
                .font(.system(size: 10, weight: .semibold))
                .padding(.top, 2)
            Text(text)
                .font(.system(size: 11.5))
                .fixedSize(horizontal: false, vertical: true)
        }
        .foregroundStyle(tint)
    }

    // MARK: - Actions

    private var selectedSkill: ComponentSkill? {
        selectedSkillId.flatMap { framework?.skill(id: $0) }
    }

    private var recentSkills: [ComponentSkill] {
        state.recentSkillIds.prefix(5).compactMap { framework?.skill(id: $0) }
    }

    private var suggestions: [ComponentSkill] {
        guard workText.count >= WorkDocument.minimumCharacters else { return [] }
        return frameworks.suggestions(for: workText)
    }

    private var characterCount: String {
        "\(workText.count) characters"
    }

    /// A soft check only — the teacher can label it however they like, but the
    /// promise that a check isn't filed against a child is worth defending.
    private var namesAStudent: Bool {
        let label = workLabel.lowercased()
        guard label.count > 2 else { return false }
        return state.classroom.classes
            .flatMap(\.students)
            .contains { student in
                let name = student.name.trimmingCharacters(in: .whitespaces).lowercased()
                return !name.isEmpty && label.contains(name)
            }
    }

    private var canRun: Bool {
        !runner.phase.isRunning
            && !state.isStreaming
            && frameworks.phase == .ready
            && selectedSkill != nil
            && workText.count >= WorkDocument.minimumCharacters
            && state.modelAvailable
    }

    private func startNewCheck() {
        openedEvaluation = nil
        workText = ""
        workLabel = ""
        sourceName = nil
        selectedSkillId = nil
        skillQuery = ""
        intakeProblem = nil
        runner.reset()
        mode = .run
    }

    private func start() {
        guard let skill = selectedSkill, let framework else { return }
        do {
            let work = try WorkDocument(text: workText, sourceName: sourceName)
            intakeProblem = nil
            runner.run(work: work, skill: skill, framework: framework,
                       workLabel: workLabel, state: state)
        } catch {
            intakeProblem = error.localizedDescription
        }
    }

    private func save(_ result: SkillEvaluation) {
        state.skillEvaluations.insert(result, at: 0)
        state.recentSkillIds.removeAll { $0 == result.skillId }
        state.recentSkillIds.insert(result.skillId, at: 0)
        runner.reset()
        mode = .list
    }

    private func setTeacherLevel(_ ordinal: Int) {
        guard var result = openedEvaluation ?? runner.result, result.effectiveLevel != ordinal else { return }
        result.teacherLevel = ordinal
        // Saved checks are updated in place; an unsaved one just re-renders.
        if let i = state.skillEvaluations.firstIndex(where: { $0.id == result.id }) {
            state.skillEvaluations[i] = result
        }
        if openedEvaluation != nil { openedEvaluation = result } else { runner.applyTeacherLevel(ordinal) }
    }

    /// Snapshot hook: TW_SKILLCHECK=run|result puts the screen into a state
    /// that would otherwise need typing and a model run to reach, so both
    /// layouts can be captured headlessly like the rest of the app's screens.
    private func seedForSnapshot() {
        let env = ProcessInfo.processInfo.environment
        guard let want = env["TW_SKILLCHECK"] else { return }
        mode = .run
        if let path = env["TW_SKILLCHECK_WORK"] {
            load(URL(fileURLWithPath: path))
        }
        selectedSkillId = env["TW_SKILLCHECK_SKILL"] ?? "FK.AC.2.c"
        guard want == "result", let skill = selectedSkill, let framework else { return }
        runner.seedForSnapshot(SkillEvaluation(
            id: "eval-snapshot",
            createdAt: Date(timeIntervalSince1970: 0),
            workLabel: workLabel.isEmpty ? "Mural response" : workLabel,
            workSnippet: String(workText.prefix(600)),
            workCharacterCount: workText.count,
            sourceName: sourceName,
            skillId: skill.id,
            competencyId: skill.competencyId,
            skillName: skill.name,
            competencyName: skill.competencyName,
            frameworkVersion: framework.version,
            levelOrdinal: 4,
            levelLabel: framework.levelLabel(4),
            levelDescriptor: skill.rung(4)?.descriptor ?? "",
            evidence: ["The mural kept the strike visible after the newspapers stopped covering it, and people still bring visitors to see it forty years later."],
            nextStep: "To move toward the next level, ask this student to connect the mural's argument to a second work made in a different community.",
            hasMixedEvidence: false,
            isOffTopic: false,
            teacherLevel: nil))
    }

    private func openFile() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = FileAttachment.allowedTypes
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        load(url)
    }

    private func load(_ url: URL) {
        guard let text = FileAttachment.extractText(from: url, limit: WorkDocument.maxCharacters) else {
            intakeProblem = "Couldn't read any text from \(url.lastPathComponent). "
                + "If it's a scan or a photo, paste the text instead."
            return
        }
        workText = text
        sourceName = url.lastPathComponent
        intakeProblem = nil
        if workLabel.isEmpty {
            workLabel = url.deletingPathExtension().lastPathComponent
        }
    }
}

/// Wrapping row of chips. SwiftUI has no built-in for this on macOS 14.
struct FlowRow<Content: View>: View {
    var spacing: CGFloat = 6
    @ViewBuilder var content: Content

    var body: some View {
        HStack(spacing: spacing) { content }
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}
