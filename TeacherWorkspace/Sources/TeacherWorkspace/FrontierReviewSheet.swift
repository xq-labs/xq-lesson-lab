import SwiftUI
import AppKit

/// The sheet that stands between a teacher's document and the internet.
///
/// Its whole job is that the payload is a *document*, not a promise: the real
/// bytes, editable, with the removals shown as removals. There is no "don't
/// ask again" — a remembered consent to unseen bytes is not consent. What is
/// remembered is that the explainer collapses to one line after the first use.
struct FrontierReviewSheet: View {
    enum Mode: Identifiable, Equatable {
        case needsKey(ArtifactRef?)
        case confirm(ArtifactRef)
        case settings

        var id: String {
            switch self {
            case .needsKey: return "needsKey"
            case .confirm(let ref): return "confirm-\(ref.type.rawValue)-\(ref.id)"
            case .settings: return "settings"
            }
        }
    }

    @EnvironmentObject var state: AppState
    @ObservedObject var runner: FrontierReviewRunner
    var mode: Mode
    var dismiss: () -> Void

    @State private var keyField = ""
    @State private var keyError: String?
    @State private var savingKey = false
    @State private var pendingKeyRemoval = false
    @State private var includeClassContext = false
    @State private var question = ""
    @State private var editedBody = ""
    @State private var showRemovals = false
    @State private var showAudit = false

    private var t: Theme { state.theme }
    private var provider: FrontierProvider { runner.provider }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            switch mode {
            case .needsKey(let ref): setupBody(then: ref)
            case .confirm: confirmBody
            case .settings: settingsBody
            }
        }
        .padding(20)
        .frame(width: 560)
        .background(t.card)
        .onAppear(perform: prepareIfNeeded)
    }

    // MARK: - Setup (no key yet)

    @ViewBuilder
    private func setupBody(then ref: ArtifactRef?) -> some View {
        Text("Set up second opinions")
            .font(.system(size: 16, weight: .bold))

        Text("""
            Your assistant runs on this Mac. A second opinion doesn't — it sends the \
            document you choose to Claude, a much larger AI model running on \
            Anthropic's servers.

            It costs a few cents per review, billed to your own Anthropic account. \
            You'll need an API key.

            This is off until you set it up, and nothing is ever sent without you \
            seeing it first.
            """)
            .font(.system(size: 12.5))
            .foregroundStyle(t.sub)
            .fixedSize(horizontal: false, vertical: true)

        VStack(alignment: .leading, spacing: 5) {
            Text("YOUR ANTHROPIC API KEY")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(t.dim)
            SecureField("sk-ant-…", text: $keyField)
                .textFieldStyle(.plain)
                .font(.system(size: 12.5, design: .monospaced))
                .padding(8)
                .background(RoundedRectangle(cornerRadius: 8).fill(t.input))
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(t.border))
            Text("Stored in your Mac's Keychain — the same place Safari keeps your passwords. XQ never sees it.")
                .font(.system(size: 11))
                .foregroundStyle(t.dim)
        }

        Button {
            NSWorkspace.shared.open(URL(string: "https://console.anthropic.com/settings/keys")!)
        } label: {
            Label("Get a key at console.anthropic.com", systemImage: "arrow.up.right.square")
                .font(.system(size: 12))
        }
        .buttonStyle(.plain)
        .foregroundStyle(t.accent)

        if let keyError { noticeRow(keyError, tint: t.red) }

        HStack {
            Spacer()
            Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
            Button(savingKey ? "Checking…" : "Save and continue") { saveKey(then: ref) }
                .keyboardShortcut(.defaultAction)
                .disabled(!looksLikeKey || savingKey)
        }
    }

    private var looksLikeKey: Bool {
        let trimmed = keyField.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.hasPrefix("sk-ant-") && trimmed.count > 20
    }

    private func saveKey(then ref: ArtifactRef?) {
        let trimmed = keyField.trimmingCharacters(in: .whitespacesAndNewlines)
        savingKey = true
        keyError = nil
        do {
            try Keychain.store(trimmed, in: AnthropicDirectProvider.keychainItem)
            keyField = ""
            savingKey = false
            state.frontierEnabled = true
            // Straight into the confirm sheet if they came from a document,
            // so setting up and reviewing is one flow rather than two.
            if let ref {
                state.frontierSheet = .confirm(ref)
            } else {
                state.frontierSheet = .settings
            }
        } catch {
            savingKey = false
            keyError = error.localizedDescription
        }
    }

    // MARK: - Confirm (the heart of it)

    @ViewBuilder
    private var confirmBody: some View {
        Text("Send this to Claude")
            .font(.system(size: 16, weight: .bold))

        if state.hasSeenFrontierConsent {
            Text("Goes over the internet to \(provider.host). Everything below is what gets sent, and nothing else does.")
                .font(.system(size: 12))
                .foregroundStyle(t.sub)
                .fixedSize(horizontal: false, vertical: true)
        } else {
            Text("""
                This goes over the internet to Anthropic's servers (\(provider.host)). \
                Everything below is what gets sent, and nothing else does.

                Read it. Edit it if you want to. Nothing leaves until you press Send.
                """)
                .font(.system(size: 12.5))
                .foregroundStyle(t.sub)
                .fixedSize(horizontal: false, vertical: true)
        }

        if runner.phase.isBusy, case .preparing(let stage) = runner.phase {
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text(stage).font(.system(size: 12)).foregroundStyle(t.sub)
            }
        }

        if let payload = runner.payload {
            removalsBlock(payload)
            payloadEditor(payload)
            classContextToggle
            notSendingBlock
        }

        // Named by kind, never by the matched text — the sheet must not echo
        // a student's name into a second place on screen just to report it.
        ForEach(Array(runner.blockingFindings.prefix(3))) { finding in
            noticeRow(finding.message, tint: t.red)
        }
        if case .failed(let message) = runner.phase {
            noticeRow(message, tint: t.red)
        }

        HStack {
            if case .sending(let stage) = runner.phase {
                ProgressView().controlSize(.small)
                Text(stage).font(.system(size: 12)).foregroundStyle(t.sub)
            }
            Spacer()
            Button(runner.phase.isBusy ? "Cancel" : "Cancel") {
                if runner.phase.isBusy { runner.cancel() } else { dismiss() }
            }
            .keyboardShortcut(.cancelAction)
            Button("Send to Claude") { send() }
                .keyboardShortcut(.defaultAction)
                .disabled(!runner.canSend || runner.phase.isBusy)
        }
    }

    /// The diff. `Name → Student A` reads as an action taken on the teacher's
    /// behalf; an absence would teach nothing.
    @ViewBuilder
    private func removalsBlock(_ payload: ReviewPayload) -> some View {
        if payload.redactions.isEmpty && payload.flagged.isEmpty {
            Text("Nothing needed removing — this document doesn't name anyone.")
                .font(.system(size: 11.5))
                .foregroundStyle(t.dim)
        } else {
            VStack(alignment: .leading, spacing: 6) {
                Button {
                    withAnimation(.easeOut(duration: 0.12)) { showRemovals.toggle() }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: showRemovals ? "chevron.down" : "chevron.right")
                            .font(.system(size: 9, weight: .bold))
                        Text("\(payload.redactions.count) thing\(payload.redactions.count == 1 ? "" : "s") removed")
                            .font(.system(size: 12, weight: .semibold))
                        Spacer()
                    }
                    .foregroundStyle(t.warn)
                }
                .buttonStyle(.plain)

                if showRemovals {
                    ForEach(payload.redactions) { redaction in
                        HStack(spacing: 6) {
                            Image(systemName: "delete.left")
                                .font(.system(size: 10))
                                .foregroundStyle(t.warn)
                            Text(redaction.original).font(.system(size: 12, weight: .medium))
                            Image(systemName: "arrow.right").font(.system(size: 9))
                                .foregroundStyle(t.dim)
                            Text(redaction.replacement).font(.system(size: 12))
                                .foregroundStyle(t.sub)
                            if redaction.count > 1 {
                                Text("×\(redaction.count)").font(.system(size: 11))
                                    .foregroundStyle(t.dim)
                            }
                            Spacer()
                        }
                    }
                    Text("Names from your roster are swapped out automatically.")
                        .font(.system(size: 11))
                        .foregroundStyle(t.dim)
                }

                // Ordinary words that are also names, and names the roster
                // doesn't know. Both are the teacher's call, not the app's.
                ForEach(payload.flagged) { flagged in
                    Text("“\(flagged.original)” is also an ordinary word, so it was left as-is.")
                        .font(.system(size: 11))
                        .foregroundStyle(t.warn)
                }
                if !payload.advisories.isEmpty {
                    Text("\(payload.advisories.count) possible name\(payload.advisories.count == 1 ? "" : "s") the app doesn't recognise from your roster — worth a look before sending.")
                        .font(.system(size: 11))
                        .foregroundStyle(t.warn)
                }
            }
            .padding(10)
            .background(RoundedRectangle(cornerRadius: 8).fill(t.warnSoft))
        }
    }

    /// Editable on purpose. "Only what you allow" is a lie if the only options
    /// are all or nothing.
    @ViewBuilder
    private func payloadEditor(_ payload: ReviewPayload) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack {
                Text("WHAT'S BEING SENT")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(t.dim)
                Spacer()
                Text("\(payload.wordCount) words · \(payload.byteCount) bytes")
                    .font(.system(size: 10))
                    .foregroundStyle(t.dim)
            }
            TextEditor(text: Binding(
                get: { editedBody.isEmpty ? payload.body : editedBody },
                set: { editedBody = $0; runner.applyEdit(body: $0, question: question) }))
                .font(.system(size: 11.5, design: .monospaced))
                .scrollContentBackground(.hidden)
                .padding(8)
                .frame(minHeight: 200, maxHeight: 260)
                .background(RoundedRectangle(cornerRadius: 8).fill(t.input))
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(
                    runner.blockingFindings.isEmpty ? t.border : t.red))
            Text("You can edit this. Delete anything you don't want to send.")
                .font(.system(size: 11))
                .foregroundStyle(t.dim)
        }
    }

    @ViewBuilder
    private var classContextToggle: some View {
        Toggle(isOn: $includeClassContext) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Include anonymous class context")
                    .font(.system(size: 12))
                Text(runner.payload?.profile?.summaryLine
                     ?? "Counts only — prepared on this Mac, no names.")
                    .font(.system(size: 11))
                    .foregroundStyle(t.dim)
            }
        }
        .toggleStyle(.checkbox)
        .onChange(of: includeClassContext) { _, _ in
            guard case .confirm(let ref) = mode else { return }
            editedBody = ""
            runner.prepare(ref: ref, includeClassContext: includeClassContext, state: state)
        }
    }

    @ViewBuilder
    private var notSendingBlock: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("WHAT'S NOT BEING SENT")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(t.dim)
            ForEach([
                "Your roster and your notes about students",
                "Your other chats and documents",
                "Your name, your school, your email",
                "Anything from Skill Check — student work never leaves this Mac, ever",
            ], id: \.self) { line in
                HStack(alignment: .top, spacing: 6) {
                    Image(systemName: "checkmark")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(t.green)
                    Text(line).font(.system(size: 11.5)).foregroundStyle(t.sub)
                    Spacer()
                }
            }
        }
    }

    // MARK: - Settings

    @ViewBuilder
    private var settingsBody: some View {
        Text("Second opinions")
            .font(.system(size: 16, weight: .bold))

        Text("""
            Your assistant runs on this Mac and stays here. A second opinion is the \
            one exception: you start it by hand, on one document at a time, and you \
            see exactly what goes before it sends.

            Student work in Skill Check is never sent, at all.
            """)
            .font(.system(size: 12.5))
            .foregroundStyle(t.sub)
            .fixedSize(horizontal: false, vertical: true)

        VStack(alignment: .leading, spacing: 6) {
            settingRow("Reviewer", provider.modelDisplayName)
            settingRow("Sends to", provider.host)
            settingRow("Billed to", "Your own Anthropic account")
            settingRow("Sent so far", "\(FrontierAuditLog.sendCount) review\(FrontierAuditLog.sendCount == 1 ? "" : "s")")
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 8).fill(t.input))

        Text("If your school network blocks outside services, ask IT to allow \(provider.host). Nothing else in the app needs it.")
            .font(.system(size: 11))
            .foregroundStyle(t.dim)
            .fixedSize(horizontal: false, vertical: true)

        HStack(spacing: 10) {
            Button("View log…") { showAudit = true }
            Button("Export log…") { exportLog() }
            Spacer()
        }
        .font(.system(size: 12))

        HStack {
            Button("Remove key", role: .destructive) { pendingKeyRemoval = true }
            Spacer()
            Button("Done") { dismiss() }.keyboardShortcut(.defaultAction)
        }
        .alert("Remove your API key?", isPresented: $pendingKeyRemoval) {
            Button("Cancel", role: .cancel) { pendingKeyRemoval = false }
            Button("Remove", role: .destructive) { removeKey() }
        } message: {
            Text("This deletes the key from your Keychain. Reviews you've already "
                 + "saved stay where they are, and the log stays too — the second "
                 + "opinion button disappears until you add a key again.")
        }
        .sheet(isPresented: $showAudit) {
            FrontierAuditView(dismiss: { showAudit = false })
                .environmentObject(state)
        }
    }

    @ViewBuilder
    private func settingRow(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label).font(.system(size: 11.5)).foregroundStyle(t.dim)
            Spacer()
            Text(value).font(.system(size: 11.5)).foregroundStyle(t.text)
        }
    }

    private func removeKey() {
        pendingKeyRemoval = false
        try? Keychain.delete(AnthropicDirectProvider.keychainItem)
        state.frontierEnabled = false
        dismiss()
    }

    private func exportLog() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.plainText]
        panel.nameFieldStringValue = "off-device-review-log.md"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        try? FrontierAuditLog.markdownTranscript().write(to: url, atomically: true,
                                                         encoding: .utf8)
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    // MARK: - Shared

    @ViewBuilder
    private func noticeRow(_ text: String, tint: Color) -> some View {
        HStack(alignment: .top, spacing: 6) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 11))
                .foregroundStyle(tint)
            Text(text)
                .font(.system(size: 11.5))
                .foregroundStyle(tint)
                .fixedSize(horizontal: false, vertical: true)
            Spacer()
        }
    }

    private func prepareIfNeeded() {
        guard case .confirm(let ref) = mode, runner.payload == nil else { return }
        runner.prepare(ref: ref, includeClassContext: includeClassContext, state: state)
    }

    private func send() {
        state.hasSeenFrontierConsent = true
        runner.send()
    }
}
