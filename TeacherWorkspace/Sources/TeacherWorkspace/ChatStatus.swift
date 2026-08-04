import SwiftUI

/// Where a conversation stands, derived from state the app already tracks —
/// nothing here is stored or hand-set, so a chat can't sit on a stale label.
///
/// Only one status shows at a time; `AppState.status(for:)` resolves them in
/// priority order (live generation first, then things that need attention,
/// then whose turn it is).
enum ChatStatus: Equatable {
    /// The on-device model is generating into this chat right now.
    case receiving
    /// The assistant ended its turn with a question — the ball is the
    /// teacher's. Derived from the text, so answering clears it on its own.
    case waiting
    /// Generation was cancelled part-way (switching chats stops the model),
    /// leaving a partial reply.
    case interrupted
    /// The last turn ended in an error rather than a reply.
    case failed

    /// Header wording, where there's room for the full phrase.
    var label: String {
        switch self {
        case .receiving: return "Receiving"
        case .waiting: return "Waiting for you"
        case .interrupted: return "Stopped"
        case .failed: return "Needs a retry"
        }
    }

    /// Sidebar wording. Rows are 200–460pt wide and the title has to keep most
    /// of that, so the phrasing tightens rather than the title truncating.
    var shortLabel: String {
        switch self {
        case .receiving: return "Receiving"
        case .waiting: return "Your turn"
        case .interrupted: return "Stopped"
        case .failed: return "Retry"
        }
    }

    func tint(_ t: Theme) -> Color {
        switch self {
        case .receiving: return t.accent
        case .waiting: return t.green
        case .interrupted: return t.dim
        case .failed: return t.red
        }
    }

    var help: String {
        switch self {
        case .receiving: return "The assistant is writing a reply"
        case .waiting: return "The assistant asked you something"
        case .interrupted: return "Generation stopped before the reply finished"
        case .failed: return "The last reply didn't come through — send again to retry"
        }
    }
}

/// Status chip, cut from the same cloth as the sidebar's version badge: 10pt
/// semibold in a soft capsule, tinted by status. `compact` picks the shorter
/// wording for sidebar rows.
struct StatusBadge: View {
    var status: ChatStatus
    var theme: Theme
    var compact: Bool = false

    @State private var pulsing = false

    private var tint: Color { status.tint(theme) }

    var body: some View {
        HStack(spacing: 4) {
            if status == .receiving {
                Circle()
                    .fill(tint)
                    .frame(width: 5, height: 5)
                    .opacity(pulsing ? 0.3 : 1)
                    .animation(.easeInOut(duration: 0.75).repeatForever(autoreverses: true),
                               value: pulsing)
                    .onAppear { pulsing = true }
            }
            Text(compact ? status.shortLabel : status.label)
                .font(.system(size: 10, weight: .semibold))
        }
        .foregroundStyle(tint)
        .padding(.vertical, 2)
        .padding(.horizontal, 6)
        // Theme only carries a soft wash for the accent, so the tint supplies
        // its own here — a touch stronger in dark, where washes read fainter.
        .background(Capsule().fill(tint.opacity(theme.isDark ? 0.16 : 0.12)))
        .fixedSize()
        .help(status.help)
    }
}
