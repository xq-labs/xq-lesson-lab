import SwiftUI

/// First-launch welcome tour. Auto-opens once on a fresh install and stays
/// reachable from the header's "?" button and the Help menu.
struct OnboardingView: View {
    @EnvironmentObject var state: AppState
    private var t: Theme { state.theme }
    @State private var page = 0

    private var pages: [OnboardingPage] { OnboardingPage.all }
    private var isLast: Bool { page == pages.count - 1 }

    var body: some View {
        ZStack {
            t.scrim
                .ignoresSafeArea()
                .onTapGesture { state.dismissOnboarding() }
            card
        }
    }

    private var card: some View {
        VStack(spacing: 0) {
            pageContent(pages[page])
                .id(page)
                .transition(.opacity)
                // Top-aligned fixed height so the card doesn't resize as the
                // pages change under it.
                .frame(height: 400, alignment: .top)
            footer
        }
        .frame(width: 600)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(t.card))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(t.border))
        .shadow(color: .black.opacity(t.isDark ? 0.5 : 0.22), radius: 40, y: 24)
        .overlay(alignment: .topTrailing) { closeButton }
        .animation(.easeOut(duration: 0.15), value: page)
        // Swallow taps so the scrim's tap-to-dismiss doesn't fire.
        .onTapGesture {}
    }

    private var closeButton: some View {
        Button {
            state.dismissOnboarding()
        } label: {
            Image(systemName: "xmark")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(t.sub)
                .frame(width: 30, height: 30)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .hoverHighlight(radius: 8, hover: t.hover)
        .keyboardShortcut(.cancelAction)
        .padding(10)
        .help("Close the tour")
    }

    private func pageContent(_ p: OnboardingPage) -> some View {
        VStack(spacing: 6) {
            Image(systemName: p.icon)
                .font(.system(size: 26, weight: .medium))
                .foregroundStyle(t.accent)
                .frame(width: 64, height: 64)
                .background(Circle().fill(t.accentSoft))
                .padding(.bottom, 10)
            Text(p.title)
                .font(.system(size: 21, weight: .bold))
            Text(p.blurb)
                .font(.system(size: 13.5))
                .foregroundStyle(t.sub)
                .multilineTextAlignment(.center)
            VStack(spacing: 12) {
                ForEach(p.features, id: \.title) { f in
                    featureRow(f)
                }
            }
            .padding(.top, 18)
        }
        .padding(.top, 36)
        .padding(.horizontal, 44)
    }

    private func featureRow(_ f: OnboardingPage.Feature) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: f.icon)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(t.accent)
                .frame(width: 30, height: 30)
                .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(t.accentSoft))
            VStack(alignment: .leading, spacing: 1) {
                Text(f.title)
                    .font(.system(size: 13, weight: .semibold))
                Text(f.detail)
                    .font(.system(size: 12.5))
                    .foregroundStyle(t.sub)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
    }

    private var footer: some View {
        HStack(spacing: 8) {
            HStack(spacing: 6) {
                ForEach(pages.indices, id: \.self) { i in
                    Circle()
                        .fill(i == page ? t.accent : t.border)
                        .frame(width: 7, height: 7)
                        .onTapGesture { page = i }
                }
            }
            Spacer()
            if page > 0 {
                Button {
                    page -= 1
                } label: {
                    Text("Back")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(t.sub)
                        .padding(.vertical, 7)
                        .padding(.horizontal, 14)
                        .contentShape(RoundedRectangle(cornerRadius: 8))
                }
                .buttonStyle(.plain)
                .hoverHighlight(radius: 8, hover: t.hover)
            }
            Button {
                if isLast {
                    state.dismissOnboarding()
                } else {
                    page += 1
                }
            } label: {
                Text(isLast ? "Get started" : "Next")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(t.sendFg)
                    .padding(.vertical, 7)
                    .padding(.horizontal, 16)
                    .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(t.sendBg))
                    .contentShape(RoundedRectangle(cornerRadius: 8))
            }
            .buttonStyle(.plain)
            .keyboardShortcut(.defaultAction)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
        .overlay(alignment: .top) {
            Rectangle().fill(t.border).frame(height: 1)
        }
    }
}

/// Static tour copy, one entry per page.
private struct OnboardingPage {
    struct Feature {
        var icon: String
        var title: String
        var detail: String
    }

    var icon: String
    var title: String
    var blurb: String
    var features: [Feature]

    static let all: [OnboardingPage] = [
        OnboardingPage(
            icon: "graduationcap",
            title: "Welcome to \(AppInfo.productName)",
            blurb: "An AI planning assistant made for teachers — your work stays on your Mac.",
            features: [
                Feature(icon: "lock.shield",
                        title: "Private by design",
                        detail: "The AI model runs entirely on this Mac. Chats, rosters, and student notes stay here — nothing is sent anywhere unless you ask for a second opinion and approve exactly what goes."),
                Feature(icon: "wifi.slash",
                        title: "Works offline",
                        detail: "No account, no cloud, no internet required — plan from anywhere."),
                Feature(icon: "sparkles",
                        title: "Sample classroom included",
                        detail: "You're looking at Dana Alvarez's demo classroom. Explore freely — you can make it your own at any time."),
            ]),
        OnboardingPage(
            icon: "bubble.left.and.bubble.right",
            title: "Chat that makes real things",
            blurb: "Ask for classroom materials and they arrive as editable cards, not walls of text.",
            features: [
                Feature(icon: "wand.and.stars",
                        title: "Rubrics, activities, quizzes & more",
                        detail: "Ask for a rubric, lesson plan, exit ticket, or PoG draft — each one is saved to its library automatically."),
                Feature(icon: "at",
                        title: "@mention what you mean",
                        detail: "Type @ to reference a student, class, rubric, or activity — the assistant works from the real thing behind the name."),
                Feature(icon: "paperclip",
                        title: "Attach and dictate",
                        detail: "Drop in files for context, or use the mic to talk instead of type."),
            ]),
        OnboardingPage(
            icon: "books.vertical",
            title: "Your libraries & preview",
            blurb: "Everything you make is organized and ready to reuse.",
            features: [
                Feature(icon: "tablecells",
                        title: "Libraries in the sidebar",
                        detail: "Rubrics, Activities, Quizzes, and Portraits of a Graduate each have a home — nothing gets lost in chat history."),
                Feature(icon: "sidebar.trailing",
                        title: "Preview panel",
                        detail: "Click any card to open it beside the chat, with tabs for comparing and in-place editing (⇧⌘P toggles it)."),
                Feature(icon: "square.and.arrow.up",
                        title: "Export and share",
                        detail: "Turn any artifact into a PDF or markdown to print or send."),
            ]),
        OnboardingPage(
            icon: "person.2",
            title: "Make it yours",
            blurb: "Set up your real classroom and the assistant plans with your students in mind.",
            features: [
                Feature(icon: "person.crop.circle.badge.plus",
                        title: "My Classroom",
                        detail: "Add your name, classes, and roster — or import students straight from a CSV."),
                Feature(icon: "folder",
                        title: "Stay organized",
                        detail: "Group chats into folders and archive what's done, right from the sidebar."),
                Feature(icon: "magnifyingglass",
                        title: "Find anything fast",
                        detail: "⌘K searches every chat and library at once. Reopen this tour anytime from the ? button up top."),
            ]),
    ]
}
