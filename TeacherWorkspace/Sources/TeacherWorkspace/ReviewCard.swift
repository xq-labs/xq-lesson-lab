import SwiftUI
import AppKit

/// A saved second opinion, shown above the document it's about so the two
/// read together.
///
/// Nothing here writes to the artifact. A cloud model silently rewriting a
/// teacher's lesson is exactly the thing that would burn the trust this
/// feature spends — every action is copy-to-clipboard or jump-to-editor, and
/// both need a keystroke from the teacher.
struct ReviewCard: View {
    @EnvironmentObject var state: AppState
    var review: FrontierReview
    /// Jumps the panel into edit mode on a numbered step.
    var editStep: (Int) -> Void
    var onDelete: () -> Void

    @State private var expanded = false
    @State private var showReceipt = false
    @State private var copiedTitle: String?
    @State private var confirmDelete = false

    private var t: Theme { state.theme }

    /// Pseudonyms render back to real first names on screen; the stored text
    /// stays de-identified.
    private func shown(_ text: String) -> String {
        review.personalized(text, classroom: state.classroom)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            if expanded {
                VStack(alignment: .leading, spacing: 14) {
                    if !review.strengths.isEmpty { strengthsSection }
                    if !review.suggestions.isEmpty { suggestionsSection }
                    if !review.questions.isEmpty { questionsSection }
                    provenance
                }
                .padding(.horizontal, 14)
                .padding(.bottom, 14)
            }
        }
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(t.card))
        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).stroke(t.border))
        .alert("Delete this review?", isPresented: $confirmDelete) {
            Button("Cancel", role: .cancel) { confirmDelete = false }
            Button("Delete", role: .destructive) { onDelete() }
        } message: {
            Text("This removes the review and the copy of what was sent. Your "
                 + "document is untouched, and the entry in the log stays — the "
                 + "record of what left this Mac isn't yours to erase from here.")
        }
        .onAppear { expanded = !state.hasSeenReview(review.id) }
    }

    private var header: some View {
        Button {
            withAnimation(.easeOut(duration: 0.14)) { expanded.toggle() }
            state.markReviewSeen(review.id)
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "cloud")
                    .font(.system(size: 11))
                    .foregroundStyle(t.warn)
                Text("\(review.modelDisplayName) reviewed this on \(review.dateLine)")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(t.text)
                Text("· \(review.summaryLine)")
                    .font(.system(size: 11.5))
                    .foregroundStyle(t.sub)
                Spacer()
                Image(systemName: expanded ? "chevron.up" : "chevron.down")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(t.dim)
            }
            .padding(14)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var strengthsSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            sectionLabel("STRENGTHS")
            ForEach(review.strengths, id: \.self) { line in
                HStack(alignment: .top, spacing: 8) {
                    Circle().fill(t.green).frame(width: 5, height: 5).padding(.top, 6)
                    Text(shown(line))
                        .font(.system(size: 12.5))
                        .foregroundStyle(t.text)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                }
            }
        }
    }

    private var suggestionsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionLabel("SUGGESTIONS")
            ForEach(Array(review.suggestions.enumerated()), id: \.offset) { index, suggestion in
                HStack(alignment: .top, spacing: 10) {
                    Text("\(index + 1)")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(t.sub)
                        .frame(width: 20, height: 20)
                        .background(Circle().fill(t.bubble))
                    VStack(alignment: .leading, spacing: 4) {
                        Text(shown(suggestion.title))
                            .font(.system(size: 12.5, weight: .semibold))
                            .fixedSize(horizontal: false, vertical: true)
                        Text(shown(suggestion.detail))
                            .font(.system(size: 12.5))
                            .foregroundStyle(t.sub)
                            .fixedSize(horizontal: false, vertical: true)
                        HStack(spacing: 10) {
                            smallButton(copiedTitle == suggestion.title ? "Copied" : "Copy") {
                                copy(suggestion)
                            }
                            if let step = suggestion.stepNumber,
                               review.subjectRef.type.supportsEditing,
                               state.isUserArtifact(review.subjectRef) {
                                smallButton("Edit step \(step)") { editStep(step) }
                            }
                        }
                        .padding(.top, 2)
                    }
                    Spacer(minLength: 0)
                }
            }
        }
    }

    private var questionsSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            sectionLabel("WORTH THINKING ABOUT")
            ForEach(review.questions, id: \.self) { question in
                Text(shown(question))
                    .font(.system(size: 12.5).italic())
                    .foregroundStyle(t.sub)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    /// Non-dismissible, and the disclosure below it is the single most
    /// trust-generating thing in the feature: the receipt, kept forever.
    private var provenance: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(review.provenanceLine)
                .font(.system(size: 11))
                .foregroundStyle(t.warn)
                .fixedSize(horizontal: false, vertical: true)

            Button {
                withAnimation(.easeOut(duration: 0.12)) { showReceipt.toggle() }
            } label: {
                HStack(spacing: 5) {
                    Image(systemName: showReceipt ? "chevron.down" : "chevron.right")
                        .font(.system(size: 9, weight: .bold))
                    Text("See exactly what was sent")
                        .font(.system(size: 11.5, weight: .medium))
                }
                .foregroundStyle(t.accent)
            }
            .buttonStyle(.plain)

            if showReceipt {
                ScrollView {
                    Text(review.payloadSent)
                        .font(.system(size: 10.5, design: .monospaced))
                        .foregroundStyle(t.sub)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(8)
                }
                .frame(maxHeight: 200)
                .background(RoundedRectangle(cornerRadius: 6).fill(t.input))
            }

            HStack {
                Spacer()
                Button("Delete this review") { confirmDelete = true }
                    .buttonStyle(.plain)
                    .font(.system(size: 11))
                    .foregroundStyle(t.dim)
            }
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 8).fill(t.warnSoft))
    }

    private func sectionLabel(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(t.dim)
    }

    private func smallButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(t.accent)
        }
        .buttonStyle(.plain)
    }

    private func copy(_ suggestion: ReviewSuggestion) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(
            "\(shown(suggestion.title))\n\n\(shown(suggestion.detail))", forType: .string)
        copiedTitle = suggestion.title
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { copiedTitle = nil }
    }
}
