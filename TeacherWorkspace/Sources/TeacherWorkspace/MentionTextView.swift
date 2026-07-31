import AppKit
import SwiftUI

/// The composer's input. A plain `TextField` can't tint part of its contents,
/// so this wraps `NSTextView` and re-colors resolved `@mentions` on every
/// edit. The binding stays a plain `String` — mentions are re-derived from the
/// text, so editing a name simply un-tints it rather than leaving a stale chip.
/// Lets the surrounding SwiftUI view drive the text view — the suggestion
/// list needs to insert into the live `NSTextView` so undo and the caret
/// behave, which a plain `String` binding can't express.
@MainActor
final class MentionFieldProxy: ObservableObject {
    weak var coordinator: MentionTextView.Coordinator?

    func insert(_ mention: Mention, at start: Int) {
        coordinator?.insert(mention, at: start)
    }

    /// Re-evaluates whether the caret sits inside an `@query`. Called once the
    /// field appears so a pre-filled draft opens the picker the same way
    /// typing would.
    func refreshQuery() {
        coordinator?.updateQuery()
    }
}

struct MentionTextView: NSViewRepresentable {
    @Binding var text: String
    var proxy: MentionFieldProxy
    var catalog: [Mention]
    var placeholder: String
    var theme: Theme
    /// True while the suggestion list is showing, so ↑/↓/⏎/esc drive it
    /// instead of the text.
    var pickerOpen: Bool
    var onSubmit: () -> Void
    var onQueryChange: (_ start: Int, _ query: String) -> Void
    var onQueryEnd: () -> Void
    var onMove: (_ delta: Int) -> Void
    var onAccept: () -> Void
    var onCancel: () -> Void

    func makeNSView(context: Context) -> AutoGrowingTextView {
        let view = AutoGrowingTextView()
        view.isRichText = false
        view.allowsUndo = true
        view.drawsBackground = false
        view.textContainerInset = .zero
        view.textContainer?.lineFragmentPadding = 0
        view.font = .systemFont(ofSize: 14.5)
        // The field is full of proper nouns — student names, artifact titles.
        // macOS substitution happily rewrites those out from under the teacher
        // (it turned "@Ma" into "@Maresi" during testing).
        view.isAutomaticTextReplacementEnabled = false
        view.isAutomaticSpellingCorrectionEnabled = false
        view.isAutomaticTextCompletionEnabled = false
        view.isAutomaticQuoteSubstitutionEnabled = false
        view.isAutomaticDashSubstitutionEnabled = false
        view.isContinuousSpellCheckingEnabled = false
        view.string = text
        // Delegate last: assigning the text above would otherwise report an
        // edit back into SwiftUI mid-construction.
        view.setSelectedRange(NSRange(location: (text as NSString).length, length: 0))
        view.delegate = context.coordinator
        context.coordinator.view = view
        proxy.coordinator = context.coordinator
        context.coordinator.highlight()
        return view
    }

    func updateNSView(_ view: AutoGrowingTextView, context: Context) {
        context.coordinator.parent = self
        proxy.coordinator = context.coordinator
        view.placeholder = placeholder
        view.placeholderColor = NSColor(theme.dim)
        if view.string != text {
            let caret = view.selectedRange().location
            let wasAtEnd = caret >= (view.string as NSString).length
            view.string = text
            // Replaced from outside — dictation, or a seeded draft. Keep the
            // caret trailing the new text so the next keystroke lands after
            // it rather than back at the start.
            let end = (text as NSString).length
            view.setSelectedRange(NSRange(location: wasAtEnd ? end : min(caret, end), length: 0))
        }
        context.coordinator.highlight()
    }

    /// Without this the text view stretches to whatever height SwiftUI offers,
    /// which in the composer is the whole chat pane.
    func sizeThatFits(_ proposal: ProposedViewSize, nsView: AutoGrowingTextView, context: Context) -> CGSize? {
        let width = proposal.width ?? nsView.bounds.width
        guard width > 0 else { return nil }
        return CGSize(width: width, height: nsView.height(forWidth: width))
    }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: MentionTextView
        weak var view: AutoGrowingTextView?
        /// The `@` offset of a mention we just completed — its picker stays
        /// closed until the teacher starts a new one.
        private var dismissedStart: Int?
        private var isHighlighting = false

        init(_ parent: MentionTextView) { self.parent = parent }

        func textDidChange(_ notification: Notification) {
            guard !isHighlighting, let view else { return }
            parent.text = view.string
            highlight()
            updateQuery()
        }

        func textViewDidChangeSelection(_ notification: Notification) {
            guard !isHighlighting else { return }
            updateQuery()
        }

        /// Replaces the in-progress `@query` with the chosen name.
        func insert(_ mention: Mention, at start: Int) {
            guard let view else { return }
            let ns = view.string as NSString
            let caret = view.selectedRange().location
            guard start <= caret, caret <= ns.length else { return }
            let replacement = "@\(mention.name) "
            let range = NSRange(location: start, length: caret - start)
            if view.shouldChangeText(in: range, replacementString: replacement) {
                view.textStorage?.replaceCharacters(in: range, with: replacement)
                view.didChangeText()
            }
            view.setSelectedRange(NSRange(location: start + (replacement as NSString).length, length: 0))
            dismissedStart = start
            parent.text = view.string
            highlight()
            parent.onQueryEnd()
        }

        func highlight() {
            guard let view, let storage = view.textStorage else { return }
            isHighlighting = true
            defer { isHighlighting = false }
            let full = NSRange(location: 0, length: storage.length)
            let body = NSFont.systemFont(ofSize: 14.5)
            storage.beginEditing()
            storage.setAttributes([.font: body, .foregroundColor: NSColor(parent.theme.text)], range: full)
            for match in MentionScanner.matches(in: view.string, catalog: parent.catalog) {
                storage.addAttributes([
                    .foregroundColor: NSColor(parent.theme.accent),
                    .font: NSFont.systemFont(ofSize: 14.5, weight: .semibold),
                    .backgroundColor: NSColor(parent.theme.accentSoft),
                ], range: match.range)
            }
            storage.endEditing()
            // Without this, text typed straight after a mention inherits its tint.
            view.typingAttributes = [.font: body, .foregroundColor: NSColor(parent.theme.text)]
            view.invalidateIntrinsicContentSize()
        }

        func updateQuery() {
            guard let view else { return }
            let caret = view.selectedRange().location
            guard let found = MentionScanner.activeQuery(in: view.string, caret: caret) else {
                dismissedStart = nil
                parent.onQueryEnd()
                return
            }
            if found.start == dismissedStart {
                parent.onQueryEnd()
                return
            }
            dismissedStart = nil
            parent.onQueryChange(found.start, found.query)
        }

        func textView(_ textView: NSTextView, doCommandBy selector: Selector) -> Bool {
            switch selector {
            case #selector(NSResponder.insertNewline(_:)):
                if parent.pickerOpen { parent.onAccept() } else { parent.onSubmit() }
                return true
            case #selector(NSResponder.moveUp(_:)):
                guard parent.pickerOpen else { return false }
                parent.onMove(-1)
                return true
            case #selector(NSResponder.moveDown(_:)):
                guard parent.pickerOpen else { return false }
                parent.onMove(1)
                return true
            case #selector(NSResponder.cancelOperation(_:)):
                guard parent.pickerOpen else { return false }
                parent.onCancel()
                return true
            case #selector(NSResponder.insertTab(_:)):
                guard parent.pickerOpen else { return false }
                parent.onAccept()
                return true
            default:
                return false
            }
        }
    }
}

/// An `NSTextView` that reports its content height so the composer grows with
/// a long message instead of scrolling a one-line box.
final class AutoGrowingTextView: NSTextView {
    var placeholder: String = ""
    var placeholderColor: NSColor = .placeholderTextColor

    private let minHeight: CGFloat = 20
    private let maxHeight: CGFloat = 140

    func height(forWidth width: CGFloat) -> CGFloat {
        guard let manager = layoutManager, let container = textContainer else { return minHeight }
        container.containerSize = NSSize(width: width, height: .greatestFiniteMagnitude)
        manager.ensureLayout(for: container)
        return min(max(manager.usedRect(for: container).height, minHeight), maxHeight)
    }

    override var intrinsicContentSize: NSSize {
        NSSize(width: NSView.noIntrinsicMetric, height: height(forWidth: bounds.width))
    }

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        invalidateIntrinsicContentSize()
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard string.isEmpty, !placeholder.isEmpty else { return }
        (placeholder as NSString).draw(
            at: NSPoint(x: 0, y: 0),
            withAttributes: [.font: font ?? .systemFont(ofSize: 14.5), .foregroundColor: placeholderColor])
    }
}
