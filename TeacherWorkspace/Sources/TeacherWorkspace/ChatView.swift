import SwiftUI

struct ChatView: View {
    @EnvironmentObject var state: AppState
    @StateObject private var dictation = DictationController()
    @StateObject private var mentionProxy = MentionFieldProxy()
    @State private var mentionSuggestions: [Mention] = []
    @State private var mentionStart = 0
    @State private var mentionIndex = 0
    @State private var pulse = false
    private var t: Theme { state.theme }

    var body: some View {
        VStack(spacing: 0) {
            if state.isWelcome {
                welcome
            } else {
                messageList
            }
            if !state.modelAvailable {
                ModelSetupCard()
            }
            composer
        }
    }

    // MARK: - Welcome

    private var welcome: some View {
        GeometryReader { _ in
            VStack(spacing: 8) {
                Spacer()
                Text(state.greeting)
                    .font(.system(size: 26, weight: .bold))
                    .kerning(-0.5)
                Text("What are we working on for your students today?")
                    .foregroundStyle(t.sub)
                    .padding(.bottom, 18)
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible())], spacing: 12) {
                    ForEach(SampleData.suggestions, id: \.title) { sug in
                        suggestionCard(sug)
                    }
                }
                .frame(maxWidth: 640)
                skillCheckCard
                    .frame(maxWidth: 640)
                    .padding(.top, 12)
                if state.classroom.isDemo {
                    Button {
                        state.setView(.classroom)
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "sparkles")
                            Text("You're seeing demo data — set up My Classroom so replies fit your real students")
                            Image(systemName: "arrow.right")
                        }
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(t.accent)
                        .padding(.vertical, 8)
                        .padding(.horizontal, 14)
                        .background(Capsule().fill(t.accentSoft))
                    }
                    .buttonStyle(.plain)
                    .padding(.top, 18)
                }
                Spacer()
            }
            .frame(maxWidth: .infinity)
            .padding(24)
        }
    }

    /// The mastery layer's front door — a navigation card, not a prompt seed,
    /// so it sits apart from the chat suggestions above it.
    private var skillCheckCard: some View {
        Button {
            state.setView(.skillCheck)
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "checkmark.seal")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(t.accent)
                VStack(alignment: .leading, spacing: 3) {
                    Text("Skill Check")
                        .font(.system(size: 13.5, weight: .semibold))
                        .foregroundStyle(t.text)
                    Text("Place student work on an XQ competency progression — it drafts, you decide")
                        .font(.system(size: 12.5))
                        .foregroundStyle(t.sub)
                }
                Spacer()
                Image(systemName: "arrow.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(t.sub)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(14)
            .contentShape(RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
        .hoverHighlight(radius: 12, hover: t.hover, base: t.card)
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(t.border))
    }

    private func suggestionCard(_ sug: SampleData.Suggestion) -> some View {
        Button {
            state.draft = sug.seed
        } label: {
            VStack(alignment: .leading, spacing: 3) {
                Text(sug.title)
                    .font(.system(size: 13.5, weight: .semibold))
                    .foregroundStyle(t.text)
                Text(sug.sub)
                    .font(.system(size: 12.5))
                    .foregroundStyle(t.sub)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(14)
            .contentShape(RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
        .hoverHighlight(radius: 12, hover: t.hover, base: t.card)
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(t.border))
    }

    // MARK: - Messages

    private var messageList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(spacing: 24) {
                    ForEach(state.messages) { msg in
                        messageRow(msg)
                    }
                    if state.canRegenerate {
                        HStack {
                            Button {
                                state.regenerate()
                            } label: {
                                Label("Regenerate", systemImage: "arrow.counterclockwise")
                                    .font(.system(size: 11.5, weight: .semibold))
                                    .foregroundStyle(t.dim)
                                    .padding(.vertical, 5)
                                    .padding(.horizontal, 10)
                                    .contentShape(Capsule())
                            }
                            .buttonStyle(.plain)
                            .hoverHighlight(radius: 12, hover: t.hover)
                            .help("Try this reply again")
                            Spacer()
                        }
                    }
                    Color.clear.frame(height: 1).id("bottom")
                }
                .frame(maxWidth: 768)
                .padding(.horizontal, 24)
                .padding(.top, 24)
                .padding(.bottom, 12)
                .frame(maxWidth: .infinity)
            }
            .onChange(of: state.scrollTick) {
                withAnimation { proxy.scrollTo("bottom", anchor: .bottom) }
            }
            .onAppear {
                proxy.scrollTo("bottom", anchor: .bottom)
            }
        }
    }

    @ViewBuilder
    private func messageRow(_ msg: Message) -> some View {
        if msg.role == .user {
            HStack {
                Spacer(minLength: 0)
                VStack(alignment: .trailing, spacing: 6) {
                    if let names = msg.attachmentNames, !names.isEmpty {
                        ForEach(names, id: \.self) { name in
                            HStack(spacing: 5) {
                                Image(systemName: "paperclip")
                                    .font(.system(size: 9, weight: .semibold))
                                Text(name)
                                    .font(.system(size: 11.5, weight: .semibold))
                                    .lineLimit(1)
                            }
                            .foregroundStyle(t.accent)
                            .padding(.vertical, 4)
                            .padding(.horizontal, 9)
                            .background(Capsule().fill(t.accentSoft))
                        }
                    }
                    if !msg.text.isEmpty {
                        Text(msg.text)
                            .font(.system(size: 14))
                            .foregroundStyle(t.text)
                            .padding(.vertical, 11)
                            .padding(.horizontal, 16)
                            .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(t.bubble))
                    }
                }
                .frame(maxWidth: 560, alignment: .trailing)
            }
            .frame(maxWidth: .infinity, alignment: .trailing)
        } else {
            VStack(alignment: .leading, spacing: 12) {
                if msg.text.isEmpty && state.isStreaming {
                    if !msg.isDraftingArtifact {
                        ThinkingIndicator()
                    }
                } else {
                    Text(Self.renderMarkdown(msg.text))
                        .font(.system(size: 14.5))
                        .lineSpacing(4)
                        .foregroundStyle(t.text)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .textSelection(.enabled)
                }
                if let ref = msg.artifact, let art = state.artifact(for: ref) {
                    artifactCard(ref: ref, title: art.title, meta: art.meta)
                }
                if msg.isDraftingArtifact {
                    draftingArtifactCard
                }
                if msg.artifactParseFailed == true {
                    parseFailedNote
                }
                if let source = msg.source {
                    HStack(spacing: 6) {
                        Circle().fill(t.green).frame(width: 5, height: 5)
                        Text(source)
                            .font(.system(size: 11.5))
                            .foregroundStyle(t.dim)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var draftingArtifactCard: some View {
        HStack(spacing: 12) {
            Image(systemName: "doc.text")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(t.accent)
                .frame(width: 34, height: 34)
                .background(RoundedRectangle(cornerRadius: 9).fill(t.accentSoft))
            VStack(alignment: .leading, spacing: 2) {
                Text("Drafting artifact…")
                    .font(.system(size: 13.5, weight: .semibold))
                    .foregroundStyle(t.text)
                ThinkingIndicator()
            }
            Spacer(minLength: 8)
        }
        .padding(.vertical, 12)
        .padding(.horizontal, 14)
        .frame(maxWidth: 420)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(t.card))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(t.border))
    }

    /// Shown when the reply was an artifact-shaped block the parser couldn't
    /// read even after repair — an honest note instead of an empty bubble.
    private var parseFailedNote: some View {
        HStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(t.sub)
            VStack(alignment: .leading, spacing: 2) {
                Text("This reply didn't form a valid card")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(t.text)
                Text("The model's draft came out malformed. Regenerate to try again — smaller models occasionally do this.")
                    .font(.system(size: 12))
                    .foregroundStyle(t.sub)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 8)
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 14)
        .frame(maxWidth: 420)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(t.card))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(t.border))
    }

    private func artifactCard(ref: ArtifactRef, title: String, meta: String) -> some View {
        Button {
            state.openPreview(ref)
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "doc.text")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(t.accent)
                    .frame(width: 34, height: 34)
                    .background(RoundedRectangle(cornerRadius: 9).fill(t.accentSoft))
                VStack(alignment: .leading, spacing: 0) {
                    Text(title)
                        .font(.system(size: 13.5, weight: .semibold))
                        .foregroundStyle(t.text)
                    Text(meta)
                        .font(.system(size: 12))
                        .foregroundStyle(t.sub)
                }
                Spacer(minLength: 8)
                Text("Open →")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(t.accent)
            }
            .padding(.vertical, 12)
            .padding(.horizontal, 14)
            .frame(maxWidth: 420)
            .contentShape(RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
        .hoverHighlight(radius: 12, hover: t.hover, base: t.card)
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(t.border))
    }

    // MARK: - Composer

    private var composer: some View {
        VStack(spacing: 8) {
            if !mentionSuggestions.isEmpty {
                mentionPicker
            }
            // A floating card above the field rather than a .popover — same
            // shape as the mention picker, and unlike an NSPopover it takes
            // the app's theme and shows up in snapshots.
            if state.modelPickerOpen {
                ModelPickerPopover { state.modelPickerOpen = false }
                    .fixedSize()
                    .frame(maxWidth: .infinity, alignment: .center)
            }
            VStack(spacing: 8) {
                if let notice = state.attachmentNotice {
                    unreadableFileNotice(notice)
                }
                if !state.pendingAttachments.isEmpty {
                    attachmentChips
                }
                MentionTextView(
                    text: $state.draft,
                    proxy: mentionProxy,
                    catalog: state.mentionCatalog,
                    placeholder: dictation.isActive
                        ? "Listening…"
                        : "Work with your teaching assistant — type @ to reference a student or artifact",
                    theme: t,
                    pickerOpen: !mentionSuggestions.isEmpty,
                    onSubmit: sendFromComposer,
                    onQueryChange: { start, query in
                        mentionStart = start
                        mentionSuggestions = state.mentionSuggestions(for: query)
                        if mentionIndex >= mentionSuggestions.count { mentionIndex = 0 }
                    },
                    onQueryEnd: closeMentionPicker,
                    onMove: { delta in
                        guard !mentionSuggestions.isEmpty else { return }
                        let count = mentionSuggestions.count
                        mentionIndex = (mentionIndex + delta + count) % count
                    },
                    onAccept: acceptMention,
                    onCancel: closeMentionPicker)
                HStack(spacing: 6) {
                    plusMenu
                    Spacer()
                    micButton
                    Button {
                        if state.isStreaming {
                            state.cancelGeneration()
                        } else {
                            sendFromComposer()
                        }
                    } label: {
                        Image(systemName: state.isStreaming ? "stop.fill" : "arrow.up")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(t.sendFg)
                            .frame(width: 32, height: 32)
                            .background(Circle().fill(t.sendBg))
                    }
                    .buttonStyle(.plain)
                    .help(state.isStreaming ? "Stop" : "Send")
                }
            }
            .padding(.top, 12)
            .padding(.bottom, 10)
            .padding(.leading, 18)
            .padding(.trailing, 14)
            .background(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .fill(t.input)
                    .shadow(color: .black.opacity(0.12), radius: 5, y: 2)
            )
            .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).stroke(
                dictation.isActive ? t.red.opacity(0.55) : t.border))

            if let failure = dictation.failure {
                HStack(spacing: 8) {
                    Text("⚠️ " + failure.message)
                        .font(.system(size: 11.5))
                        .foregroundStyle(t.red)
                        .multilineTextAlignment(.center)
                    if let url = failure.settingsURL {
                        Button("Open Settings") { NSWorkspace.shared.open(url) }
                            .buttonStyle(.link)
                            .font(.system(size: 11.5, weight: .semibold))
                    }
                }
            } else if let footer = footerText {
                Text(footer)
                    .font(.system(size: 11.5))
                    .foregroundStyle(t.dim)
                    .multilineTextAlignment(.center)
            } else {
                modelButton
            }
        }
        .frame(maxWidth: 768)
        .padding(.top, 8)
        .padding(.bottom, 14)
        .padding(.horizontal, 24)
        .frame(maxWidth: .infinity)
        .onAppear {
            dictation.onText = { [weak state] text in state?.draft = text }
            // A draft restored (or seeded) with the caret inside an @query
            // should offer the picker without waiting for a keystroke.
            DispatchQueue.main.async { mentionProxy.refreshQuery() }
        }
        .onDisappear { dictation.stop() }
    }

    // MARK: - @mention picker

    private var mentionPicker: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(mentionSuggestions.enumerated()), id: \.offset) { index, mention in
                Button {
                    mentionIndex = index
                    acceptMention()
                } label: {
                    HStack(spacing: 9) {
                        Image(systemName: mention.kind.icon)
                            .font(.system(size: 11.5, weight: .medium))
                            .foregroundStyle(t.accent)
                            .frame(width: 18)
                        Text(mention.name)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(t.text)
                        Text(mention.subtitle)
                            .font(.system(size: 11.5))
                            .foregroundStyle(t.dim)
                            .lineLimit(1)
                        Spacer(minLength: 8)
                        Text(mention.kind.label)
                            .font(.system(size: 10.5, weight: .semibold))
                            .foregroundStyle(t.dim)
                    }
                    .padding(.vertical, 7)
                    .padding(.horizontal, 12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(RoundedRectangle(cornerRadius: 8)
                        .fill(index == mentionIndex ? t.accentSoft : .clear))
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(5)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(t.card)
            .shadow(color: .black.opacity(0.18), radius: 10, y: 4))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(t.border))
    }

    private func acceptMention() {
        guard mentionSuggestions.indices.contains(mentionIndex) else { return }
        mentionProxy.insert(mentionSuggestions[mentionIndex], at: mentionStart)
        closeMentionPicker()
    }

    private func closeMentionPicker() {
        mentionSuggestions = []
        mentionIndex = 0
    }

    /// Nil when the model line should be the picker button instead of prose.
    private var footerText: String? {
        if dictation.isActive { return "Listening — speech is transcribed on this Mac. Click the mic to stop." }
        return state.modelAvailable
            ? nil
            : "The assistant needs its on-device model — download it above to start chatting"
    }

    /// The model line doubles as the way in to switching models — same size
    /// and colour as the footer prose it replaced, with a chevron to say so.
    private var modelButton: some View {
        Button {
            state.modelPickerOpen = true
        } label: {
            HStack(spacing: 4) {
                Text("On-device model: \(state.activeModel.displayName) · runs privately on this Mac")
                    .font(.system(size: 11.5))
                Image(systemName: "chevron.up")
                    .font(.system(size: 9, weight: .semibold))
            }
            .foregroundStyle(t.dim)
            .padding(.vertical, 3)
            .padding(.horizontal, 8)
            .contentShape(RoundedRectangle(cornerRadius: 7))
        }
        .buttonStyle(.plain)
        .hoverHighlight(radius: 7, hover: t.hover)
        .help("Choose the model that answers")
    }

    /// ChatGPT-style "+" menu, with options that fit a teaching assistant.
    private var plusMenu: some View {
        Menu {
            Section("Add") {
                Button {
                    openAttachmentPanel()
                } label: {
                    Label("Attach file (PDF, text, CSV)…", systemImage: "paperclip")
                }
                referenceArtifactMenu
                Button {
                    state.setView(.classroom)
                } label: {
                    Label("Import roster (CSV)…", systemImage: "person.badge.plus")
                }
            }
            Section("Create") {
                Button("New rubric") { state.draft = "Draft a 4-level rubric for " }
                Button("New lesson plan") { state.draft = "Create a lesson plan for " }
                Button("New exit ticket") { state.draft = "Create a 5-question exit ticket quiz on " }
            }
        } label: {
            Image(systemName: "plus")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(t.sub)
                .frame(width: 30, height: 30)
                .contentShape(Circle())
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .hoverHighlight(radius: 15, hover: t.hover)
        .help("Add files, reference artifacts, or start a template")
    }

    @ViewBuilder
    private var referenceArtifactMenu: some View {
        let refs: [(ArtifactRef, String)] =
            state.allRubrics.prefix(5).map { (ArtifactRef(type: .rubric, id: $0.id), $0.title) }
            + state.allActivities.prefix(5).map { (ArtifactRef(type: .activity, id: $0.id), $0.title) }
            + state.allQuizzes.prefix(3).map { (ArtifactRef(type: .quiz, id: $0.id), $0.title) }
            + state.allPogs.prefix(3).map { (ArtifactRef(type: .pog, id: $0.id), $0.title) }
        if !refs.isEmpty {
            Menu {
                ForEach(refs, id: \.0.id) { ref, title in
                    Button(title) { state.attachArtifact(ref) }
                }
            } label: {
                Label("Reference an artifact", systemImage: "doc.text")
            }
        }
    }

    private func openAttachmentPanel() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = FileAttachment.allowedTypes
        panel.allowsMultipleSelection = true
        guard panel.runModal() == .OK else { return }
        for url in panel.urls {
            state.attachFile(at: url)
        }
    }

    /// Sits where the attachment chip would have gone, so the file the teacher
    /// picked accounts for itself either way.
    private func unreadableFileNotice(_ text: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 10, weight: .semibold))
            Text(text)
                .font(.system(size: 11.5, weight: .medium))
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
            Button {
                state.attachmentNotice = nil
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 8, weight: .bold))
                    .frame(width: 18, height: 18)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .foregroundStyle(t.red)
        .padding(.vertical, 5)
        .padding(.horizontal, 9)
        .background(RoundedRectangle(cornerRadius: 8, style: .continuous)
            .fill(t.red.opacity(t.isDark ? 0.16 : 0.10)))
    }

    private var attachmentChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(state.pendingAttachments) { attachment in
                    HStack(spacing: 5) {
                        Image(systemName: "paperclip")
                            .font(.system(size: 9, weight: .semibold))
                        Text(attachment.name)
                            .font(.system(size: 11.5, weight: .semibold))
                            .lineLimit(1)
                        Button {
                            state.pendingAttachments.removeAll { $0.id == attachment.id }
                        } label: {
                            Image(systemName: "xmark")
                                .font(.system(size: 8, weight: .bold))
                                .frame(width: 18, height: 18)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                    .foregroundStyle(t.accent)
                    .padding(.vertical, 4)
                    .padding(.horizontal, 9)
                    .background(Capsule().fill(t.accentSoft))
                }
            }
        }
    }

    private func sendFromComposer() {
        dictation.stop()
        dictation.clearError()
        state.send()
    }

    private var micButton: some View {
        Button {
            dictation.toggle(currentText: state.draft)
        } label: {
            Image(systemName: dictation.isActive ? "mic.fill" : "mic")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(dictation.isActive ? t.red : t.sub)
                .frame(width: 30, height: 30)
                .background(
                    Circle()
                        .fill(t.red.opacity(dictation.isActive ? 0.14 : 0))
                        .scaleEffect(pulse && dictation.isActive ? 1.0 : 0.8)
                        .animation(dictation.isActive
                                   ? .easeInOut(duration: 0.7).repeatForever(autoreverses: true)
                                   : .default,
                                   value: pulse)
                )
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .hoverHighlight(radius: 15, hover: t.hover)
        .help(dictation.isActive ? "Stop dictation" : "Dictate (English)")
        .onAppear { pulse = true }
    }

    /// Line-by-line inline markdown (bold/italic/code) that preserves list
    /// structure — full markdown parsing would collapse the newlines.
    static func renderMarkdown(_ text: String) -> AttributedString {
        var result = AttributedString()
        let lines = text.components(separatedBy: "\n")
        for (i, line) in lines.enumerated() {
            var cleaned = line
            // Simple bullet normalization for common model output.
            if let r = cleaned.range(of: #"^\s*[\*\-]\s{3,}"#, options: .regularExpression) {
                cleaned = cleaned.replacingCharacters(in: r, with: "    • ")
            } else if let r = cleaned.range(of: #"^\s*[\*\-]\s+"#, options: .regularExpression) {
                cleaned = cleaned.replacingCharacters(in: r, with: "•  ")
            } else if let r = cleaned.range(of: #"^#{1,4}\s+"#, options: .regularExpression) {
                cleaned = cleaned.replacingCharacters(in: r, with: "")
            }
            if let parsed = try? AttributedString(
                markdown: cleaned,
                options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)) {
                result += parsed
            } else {
                result += AttributedString(cleaned)
            }
            if i < lines.count - 1 { result += AttributedString("\n") }
        }
        return result
    }

    private struct ThinkingIndicator: View {
        @State private var phase = false

        var body: some View {
            HStack(spacing: 5) {
                ForEach(0..<3, id: \.self) { i in
                    Circle()
                        .fill(.secondary)
                        .frame(width: 6, height: 6)
                        .opacity(phase ? 0.25 : 0.9)
                        .animation(
                            .easeInOut(duration: 0.5).repeatForever(autoreverses: true).delay(Double(i) * 0.16),
                            value: phase)
                }
            }
            .padding(.vertical, 6)
            .onAppear { phase = true }
        }
    }

    private func composerIcon(_ systemName: String, help: String) -> some View {
        Button {} label: {
            Image(systemName: systemName)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(t.sub)
                .frame(width: 30, height: 30)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .hoverHighlight(radius: 15, hover: t.hover)
        .help(help)
    }
}
