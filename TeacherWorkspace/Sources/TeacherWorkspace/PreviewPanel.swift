import SwiftUI

struct PreviewPanel: View {
    @EnvironmentObject var state: AppState
    @State private var copied = false
    @State private var editing = false
    @State private var confirmDelete = false
    @State private var dragStartWidth: CGFloat?

    private var t: Theme { state.theme }
    private var activeRef: ArtifactRef? { state.activePreviewTab }

    private func panelButton(_ icon: String, help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(t.sub)
                .frame(width: 30, height: 30)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .hoverHighlight(radius: 7, hover: t.hover)
        .help(help)
    }

    private func title(_ ref: ArtifactRef) -> String { state.artifact(for: ref)?.title ?? "" }
    private func meta(_ ref: ArtifactRef) -> String { state.artifact(for: ref)?.meta ?? "" }

    var body: some View {
        HStack(spacing: 0) {
            resizeHandle
            VStack(alignment: .leading, spacing: 0) {
                panelBar
                if let ref = activeRef {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(title(ref))
                            .font(.system(size: 15, weight: .bold))
                        Text(meta(ref))
                            .font(.system(size: 11.5))
                            .foregroundStyle(t.dim)
                    }
                    .padding(.top, 14)
                    .padding(.horizontal, 20)
                    ScrollView {
                        VStack(alignment: .leading, spacing: 16) {
                            // Above the document, so the critique is read in
                            // relation to the thing it's about.
                            if let review = state.latestReview(for: ref) {
                                ReviewCard(review: review,
                                           editStep: { _ in editing = true },
                                           onDelete: { state.deleteReview(review.id) })
                            }
                            docContent(ref)
                        }
                        .padding(.vertical, 16)
                        .padding(.horizontal, 20)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .id(ref.id)  // fresh scroll position per tab
                } else {
                    emptyState
                }
            }
        }
        .frame(width: min(900, max(320, state.previewWidth)))
        .background(t.bg)
        .onChange(of: state.activePreviewTab) { _, _ in editing = false }
        .alert("Delete “\(activeRef.map(title) ?? "")”?", isPresented: $confirmDelete) {
            Button("Delete", role: .destructive) {
                if let ref = activeRef { state.deleteArtifact(ref) }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("It will be removed from your library. Chats that referenced it keep their text.")
        }
    }

    @ViewBuilder
    private func docContent(_ ref: ArtifactRef) -> some View {
        switch ref.type {
        case .rubric:
            if editing, let binding = state.userRubricBinding(id: ref.id) {
                rubricEditor(binding)
            } else if let r = state.rubric(id: ref.id) {
                rubricBody(r)
            }
        case .activity:
            if editing, let binding = state.userActivityBinding(id: ref.id) {
                activityEditor(binding)
            } else if let a = state.activity(id: ref.id) {
                activityBody(a)
            }
        case .pog:
            if editing, let binding = state.userPogBinding(id: ref.id) {
                pogEditor(binding)
            } else if let p = state.pog(id: ref.id) {
                pogBody(p)
            }
        case .quiz:
            if let q = state.quiz(id: ref.id) {
                quizBody(q)
            }
        case .email:
            if let e = state.email(id: ref.id) {
                emailBody(e)
            }
        }
    }

    /// Drag the panel's left edge to resize it.
    private var resizeHandle: some View {
        ZStack {
            Rectangle().fill(t.border).frame(width: 1)
        }
        .frame(width: 8)
        .frame(maxHeight: .infinity)
        .contentShape(Rectangle())
        .gesture(
            DragGesture(minimumDistance: 1, coordinateSpace: .global)
                .onChanged { value in
                    if dragStartWidth == nil { dragStartWidth = state.previewWidth }
                    let proposed = (dragStartWidth ?? 430) - value.translation.width
                    state.previewWidth = min(900, max(320, proposed))
                }
                .onEnded { _ in dragStartWidth = nil }
        )
        .onHover { inside in
            if inside { NSCursor.resizeLeftRight.push() } else { NSCursor.pop() }
        }
        .help("Drag to resize")
    }

    /// Shown when no document tab is open: the chat's artifacts, ready to open.
    private var emptyState: some View {
        let refs = state.activeChatArtifacts
        return VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                Image(systemName: "doc.text")
                    .font(.system(size: 22))
                    .foregroundStyle(t.dim)
                Text("No document open")
                    .font(.system(size: 14, weight: .semibold))
                    .padding(.top, 4)
                Text(refs.isEmpty
                     ? "Ask for a rubric, lesson plan, or quiz and it will appear here."
                     : "Artifacts from this chat:")
                    .font(.system(size: 12))
                    .foregroundStyle(t.sub)
            }
            ForEach(refs, id: \.id) { ref in
                Button {
                    state.openPreview(ref)
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: "doc.text")
                            .font(.system(size: 12))
                            .foregroundStyle(t.accent)
                            .frame(width: 28, height: 28)
                            .background(RoundedRectangle(cornerRadius: 7).fill(t.accentSoft))
                        VStack(alignment: .leading, spacing: 0) {
                            Text(title(ref))
                                .font(.system(size: 12.5, weight: .semibold))
                                .foregroundStyle(t.text)
                                .lineLimit(1)
                            Text(meta(ref))
                                .font(.system(size: 11))
                                .foregroundStyle(t.dim)
                                .lineLimit(1)
                        }
                        Spacer(minLength: 0)
                    }
                    .padding(8)
                    .contentShape(RoundedRectangle(cornerRadius: 10))
                }
                .buttonStyle(.plain)
                .hoverHighlight(radius: 10, hover: t.hover, base: t.card)
                .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).stroke(t.border))
            }
            Spacer()
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Editors (user-created artifacts only)

    private func editField(_ placeholder: String, text: Binding<String>, size: CGFloat = 12.5) -> some View {
        TextField(placeholder, text: text, axis: .vertical)
            .textFieldStyle(.plain)
            .font(.system(size: size))
            .foregroundStyle(t.text)
            .padding(.vertical, 6)
            .padding(.horizontal, 8)
            .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(t.input))
            .overlay(RoundedRectangle(cornerRadius: 7, style: .continuous).stroke(t.border))
    }

    private func rubricEditor(_ rubric: Binding<Rubric>) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            editField("Title", text: rubric.title, size: 14)
            editField("Subtitle", text: rubric.sub)
            ForEach(rubric.criteria.indices, id: \.self) { ci in
                VStack(alignment: .leading, spacing: 6) {
                    editField("Criterion name", text: rubric.criteria[ci].name, size: 13)
                    ForEach(rubric.criteria[ci].cells.indices, id: \.self) { li in
                        HStack(alignment: .top, spacing: 8) {
                            Text(SampleData.levels4[min(li, 3)])
                                .font(.system(size: 11, weight: .bold))
                                .foregroundStyle(t.dim)
                                .frame(width: 74, alignment: .leading)
                                .padding(.top, 7)
                            editField("Level description", text: rubric.criteria[ci].cells[li])
                        }
                    }
                }
                .padding(10)
                .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).stroke(t.border))
            }
        }
    }

    private func activityEditor(_ activity: Binding<Activity>) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            editField("Title", text: activity.title, size: 14)
            editField("Meta (Subject · Duration · Format)", text: activity.meta)
            editField("Description", text: activity.desc)
            Text("STEPS")
                .font(.system(size: 11, weight: .bold)).kerning(0.6).foregroundStyle(t.dim)
            ForEach(activity.steps.indices, id: \.self) { i in
                HStack(alignment: .top, spacing: 8) {
                    Text("\(i + 1).")
                        .font(.system(size: 12, weight: .bold)).foregroundStyle(t.dim)
                        .padding(.top, 7)
                    editField("Step", text: activity.steps[i])
                    Button {
                        activity.wrappedValue.steps.remove(at: i)
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 9, weight: .bold)).foregroundStyle(t.dim)
                            .frame(width: 24, height: 24)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
            Button {
                activity.wrappedValue.steps.append("")
            } label: {
                Label("Add step", systemImage: "plus")
                    .font(.system(size: 12, weight: .semibold)).foregroundStyle(t.accent)
            }
            .buttonStyle(.plain)
        }
    }

    private func pogEditor(_ pog: Binding<Pog>) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            editField("Title", text: pog.title, size: 14)
            editField("Subtitle", text: pog.sub)
            ForEach(pog.comps.indices, id: \.self) { ci in
                VStack(alignment: .leading, spacing: 6) {
                    editField("Competency", text: pog.comps[ci].name, size: 13)
                    editField("Description", text: pog.comps[ci].desc)
                }
                .padding(10)
                .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).stroke(t.border))
            }
            Text("Set levels with the dots in view mode.")
                .font(.system(size: 11)).foregroundStyle(t.dim)
        }
    }

    /// Tab strip (one chip per open document) + actions for the active one.
    private var panelBar: some View {
        HStack(spacing: 8) {
            if state.previewTabs.isEmpty {
                Text("Preview")
                    .font(.system(size: 12.5, weight: .semibold))
                    .foregroundStyle(t.dim)
                    .padding(.horizontal, 6)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 4) {
                        ForEach(state.previewTabs, id: \.id) { tab in
                            tabChip(tab)
                        }
                    }
                }
            }
            Spacer(minLength: 4)
            if let ref = activeRef {
                if state.isUserArtifact(ref) {
                    if ref.type.supportsEditing {
                        panelButton(editing ? "checkmark" : "pencil", help: editing ? "Done editing" : "Edit") {
                            editing.toggle()
                        }
                    }
                    panelButton("trash", help: "Delete from library") {
                        confirmDelete = true
                    }
                }
                // Only a teacher's own document, and only once a key exists —
                // with no key the button is absent, not disabled. The demo
                // classroom's samples can therefore never trigger a request.
                if state.frontierEnabled, state.isUserArtifact(ref) {
                    panelButton("cloud",
                                help: "Second opinion — send this to Claude over the "
                                    + "internet. You'll see exactly what gets sent first.") {
                        state.startReview(of: ref)
                    }
                }
                panelButton("doc.on.doc", help: copied ? "Copied!" : "Copy as Markdown") {
                    ArtifactExport.copyMarkdown(for: ref, state: state)
                    copied = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { copied = false }
                }
                panelButton("square.and.arrow.down", help: "Save as PDF…") {
                    ArtifactExport.savePDF(for: ref, state: state)
                }
            }
            panelButton("xmark", help: "Close preview panel") {
                state.closePreview()
            }
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 10)
        .overlay(alignment: .bottom) {
            Rectangle().fill(t.border).frame(height: 1)
        }
    }

    private func tabChip(_ tab: ArtifactRef) -> some View {
        let isActive = tab == activeRef
        return HStack(spacing: 6) {
            Image(systemName: "doc.text")
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(isActive ? t.accent : t.dim)
            Text(title(tab))
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(isActive ? t.text : t.sub)
                .lineLimit(1)
                .frame(maxWidth: 140, alignment: .leading)
            Button {
                state.closeTab(tab)
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(t.dim)
                    .frame(width: 20, height: 20)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .hoverHighlight(radius: 4, hover: t.hover)
            .help("Close tab")
        }
        .padding(.vertical, 5)
        .padding(.horizontal, 8)
        .background(RoundedRectangle(cornerRadius: 8, style: .continuous)
            .fill(isActive ? t.card : .clear))
        .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous)
            .stroke(isActive ? t.border : .clear))
        .contentShape(RoundedRectangle(cornerRadius: 8))
        .onTapGesture { state.activePreviewTab = tab }
        .help(title(tab))
    }

    // MARK: - Quiz

    private func quizBody(_ quiz: Quiz) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            ForEach(Array(quiz.questions.enumerated()), id: \.offset) { i, q in
                VStack(alignment: .leading, spacing: 6) {
                    HStack(alignment: .top, spacing: 10) {
                        Text("\(i + 1)")
                            .font(.system(size: 11.5, weight: .bold))
                            .foregroundStyle(t.accent)
                            .frame(width: 22, height: 22)
                            .background(Circle().fill(t.accentSoft))
                        Text(q.prompt)
                            .font(.system(size: 13.5, weight: .semibold))
                            .foregroundStyle(t.text)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    if !q.choices.isEmpty {
                        VStack(alignment: .leading, spacing: 4) {
                            ForEach(Array(q.choices.enumerated()), id: \.offset) { ci, choice in
                                Text("\(String(UnicodeScalar(65 + ci % 26)!)). \(choice)")
                                    .font(.system(size: 12.5))
                                    .foregroundStyle(t.sub)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                        .padding(.leading, 32)
                    }
                    if !q.answer.isEmpty {
                        Text("Answer: \(q.answer)")
                            .font(.system(size: 11.5, weight: .semibold))
                            .foregroundStyle(t.green)
                            .padding(.leading, 32)
                    }
                }
                .padding(.vertical, 10)
                .padding(.horizontal, 12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).stroke(t.border))
            }
        }
    }

    // MARK: - Email

    private func emailBody(_ email: EmailDraft) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Text("Subject:")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(t.dim)
                Text(email.title)
                    .font(.system(size: 12.5, weight: .semibold))
                    .foregroundStyle(t.text)
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(t.card))
            Text(email.body)
                .font(.system(size: 13))
                .lineSpacing(3)
                .foregroundStyle(t.text)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
            Text("Review before sending — your assistant drafts, you decide.")
                .font(.system(size: 11))
                .foregroundStyle(t.dim)
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
