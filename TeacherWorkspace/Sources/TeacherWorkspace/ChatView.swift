import SwiftUI

struct ChatView: View {
    @EnvironmentObject var state: AppState
    private var t: Theme { state.theme }

    var body: some View {
        VStack(spacing: 0) {
            if state.isWelcome {
                welcome
            } else {
                messageList
            }
            composer
        }
    }

    // MARK: - Welcome

    private var welcome: some View {
        GeometryReader { _ in
            VStack(spacing: 8) {
                Spacer()
                Text("Good morning, Dana.")
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
                Spacer()
            }
            .frame(maxWidth: .infinity)
            .padding(24)
        }
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
                Text(msg.text)
                    .font(.system(size: 14))
                    .foregroundStyle(t.text)
                    .padding(.vertical, 11)
                    .padding(.horizontal, 16)
                    .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(t.bubble))
                    .frame(maxWidth: 560, alignment: .trailing)
            }
            .frame(maxWidth: .infinity, alignment: .trailing)
        } else {
            VStack(alignment: .leading, spacing: 12) {
                Text(msg.text)
                    .font(.system(size: 14.5))
                    .lineSpacing(4)
                    .foregroundStyle(t.text)
                    .frame(maxWidth: .infinity, alignment: .leading)
                if let ref = msg.artifact, let art = state.artifact(for: ref) {
                    artifactCard(ref: ref, title: art.title, meta: art.meta)
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
            VStack(spacing: 8) {
                TextField("Work with your teaching assistant", text: $state.draft)
                    .textFieldStyle(.plain)
                    .font(.system(size: 14.5))
                    .foregroundStyle(t.text)
                    .onSubmit { state.send() }
                HStack(spacing: 6) {
                    composerIcon("plus", help: "Attach")
                    Button {} label: {
                        HStack(spacing: 6) {
                            Image(systemName: "person")
                                .font(.system(size: 11, weight: .medium))
                            Text("Class context")
                                .font(.system(size: 12.5, weight: .semibold))
                        }
                        .foregroundStyle(t.sub)
                        .padding(.horizontal, 10)
                        .frame(height: 30)
                        .contentShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    .hoverHighlight(radius: 15, hover: t.hover)
                    .help("Reference a class or student")
                    Spacer()
                    composerIcon("mic", help: "Dictate")
                    Button {
                        state.send()
                    } label: {
                        Image(systemName: "arrow.up")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(t.sendFg)
                            .frame(width: 32, height: 32)
                            .background(Circle().fill(t.sendBg))
                    }
                    .buttonStyle(.plain)
                    .help("Send")
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
            .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).stroke(t.border))

            Text("Connected: Google Classroom · Calendar · Drive · PowerSchool · Gmail")
                .font(.system(size: 11.5))
                .foregroundStyle(t.dim)
        }
        .frame(maxWidth: 768)
        .padding(.top, 8)
        .padding(.bottom, 14)
        .padding(.horizontal, 24)
        .frame(maxWidth: .infinity)
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
