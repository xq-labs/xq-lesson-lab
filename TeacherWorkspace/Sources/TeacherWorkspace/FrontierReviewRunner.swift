import SwiftUI

/// Drives one second opinion: build the payload on this Mac, hand it to the
/// consent sheet, and — only once the teacher approves — send it.
///
/// Mirrors `EvaluationRunner`, with one deliberate difference. The network
/// request does **not** take `AppState.isEvaluating`: it never touches
/// `LlamaBackend`'s serial queue, so a teacher can keep chatting with the
/// on-device model while a review is in flight. The optional class-profiling
/// stage *does* take the interlock, because that one runs locally.
@MainActor
final class FrontierReviewRunner: ObservableObject {

    enum Phase: Equatable {
        case idle
        /// Building the payload on this Mac. Nothing has left.
        case preparing(String)
        /// Waiting for the teacher to read and approve.
        case awaitingConsent
        case sending(String)
        case done
        case cancelled
        case failed(String)

        var isBusy: Bool {
            switch self {
            case .preparing, .sending: return true
            case .idle, .awaitingConsent, .done, .cancelled, .failed: return false
            }
        }
    }

    @Published private(set) var phase: Phase = .idle
    @Published private(set) var result: FrontierReview?
    /// What the sheet renders and the teacher edits.
    @Published var payload: ReviewPayload?
    /// Blocking findings from the last edit, if the gate stopped it.
    @Published private(set) var blockingFindings: [RedactionGate.Finding] = []

    let provider: FrontierProvider

    private var task: Task<Void, Never>?
    private var lexicon = PIILexicon()
    private var subjectTitle = ""

    init(provider: FrontierProvider = AnthropicDirectProvider()) {
        self.provider = provider
    }

    // MARK: - Preparing (all local)

    /// Builds the payload and stops. Nothing is sent until `send()`.
    func prepare(ref: ArtifactRef, includeClassContext: Bool, state: AppState) {
        guard !phase.isBusy else { return }
        result = nil
        blockingFindings = []
        phase = .preparing("Checking what would be sent")

        lexicon = PIILexicon.build(from: state.classroom)
        guard let markdown = ArtifactExport.markdown(for: ref, state: state),
              let title = state.artifact(for: ref)?.title else {
            phase = .failed("This document couldn't be read.")
            return
        }
        subjectTitle = title

        task = Task { [weak self] in
            guard let self else { return }
            do {
                var profile: ClassProfile?
                if includeClassContext, let section = state.classroom.classes.first(
                    where: { !$0.students.filter({ !$0.name.isEmpty }).isEmpty }) {
                    // Local model, so it shares LlamaBackend's queue with chat.
                    state.isEvaluating = true
                    defer { state.isEvaluating = false }
                    profile = try await ClassProfiler.profile(
                        section, subject: state.classroom.subject, backend: state.backend,
                        onStage: { [weak self] stage in
                            Task { @MainActor in
                                guard let self, case .preparing = self.phase else { return }
                                self.phase = .preparing(stage)
                            }
                        })
                }
                try Task.checkCancellation()
                payload = try ReviewPayload(ref: ref, title: title, markdown: markdown,
                                            profile: profile, lexicon: lexicon)
                phase = .awaitingConsent
            } catch is CancellationError {
                phase = .cancelled
            } catch let blocked as RedactionGate.Blocked {
                blockingFindings = blocked.findings
                FrontierAuditLog.recordBlocked(provider: provider, findings: blocked.findings,
                                               subject: ref, title: title)
                phase = .failed(blocked.localizedDescription)
            } catch {
                phase = .failed(error.localizedDescription)
            }
            task = nil
        }
    }

    /// Re-runs the gate after the teacher edits the payload in the sheet.
    /// This is the edit that can put a name back, so it is checked every time.
    func applyEdit(body: String, question: String?) {
        guard let current = payload else { return }
        do {
            payload = try current.edited(body: body, question: question, lexicon: lexicon)
            blockingFindings = []
        } catch let blocked as RedactionGate.Blocked {
            blockingFindings = blocked.findings
        } catch {
            blockingFindings = []
        }
    }

    var canSend: Bool {
        payload != nil && blockingFindings.isEmpty && provider.isConfigured
    }

    // MARK: - Sending

    func send() {
        guard let payload, canSend, !phase.isBusy else { return }
        phase = .sending("Sending")

        task = Task { [weak self] in
            guard let self else { return }

            // The attempt line, with the full payload, is written before the
            // request runs. A crash mid-flight must not leave a send with no
            // record of what went out.
            let auditId = FrontierAuditLog.recordAttempt(
                payload: payload, provider: provider, title: subjectTitle)
            do {
                phase = .sending("Claude is reading it…")
                let review = try await provider.review(payload, lexicon: lexicon)
                try Task.checkCancellation()

                let record = FrontierReview(
                    id: "review-\(UUID().uuidString)",
                    createdAt: Date(),
                    subjectRef: payload.subjectRef,
                    subjectTitle: subjectTitle,
                    providerId: provider.id,
                    modelId: provider.modelId,
                    modelDisplayName: provider.modelDisplayName,
                    strengths: review.strengths,
                    suggestions: review.suggestions,
                    questions: review.questions,
                    payloadSent: payload.outgoingText,
                    requestBytes: payload.byteCount,
                    auditEntryId: auditId,
                    studentIdOrder: payload.studentIdOrder)

                FrontierAuditLog.recordCompleted(
                    id: auditId, provider: provider,
                    requestBytes: payload.byteCount,
                    responseBytes: review.strengths.joined().utf8.count
                        + review.suggestions.map(\.detail).joined().utf8.count)
                result = record
                phase = .done
            } catch is CancellationError {
                FrontierAuditLog.recordFailed(id: auditId, provider: provider,
                                              requestBytes: payload.byteCount,
                                              error: FrontierError.cancelled)
                phase = .cancelled
            } catch {
                FrontierAuditLog.recordFailed(id: auditId, provider: provider,
                                              requestBytes: payload.byteCount, error: error)
                phase = .failed(error.localizedDescription)
            }
            task = nil
        }
    }

    /// Cancelling keeps the payload, so the teacher doesn't lose the sheet
    /// along with the request.
    func cancel() {
        task?.cancel()
        task = nil
        phase = payload == nil ? .cancelled : .awaitingConsent
    }

    func reset() {
        task?.cancel()
        task = nil
        payload = nil
        result = nil
        blockingFindings = []
        phase = .idle
    }

    /// Snapshot-only: drops a finished review in without running anything.
    func seedForSnapshot(_ review: FrontierReview) {
        result = review
        phase = .done
    }
}
