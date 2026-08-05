import Foundation
import llama

/// Runs a Qwen3.5 GGUF model in-process via llama.cpp (Metal). Which model is
/// the teacher's choice — see ModelCatalog. It loads lazily on first use, stays
/// resident, and reloads when the selection changes.
final class LlamaBackend: ChatBackend, @unchecked Sendable {
    static let shared = LlamaBackend()

    private let queue = DispatchQueue(label: "llama.generation", qos: .userInitiated)
    private var model: OpaquePointer?
    private var ctx: OpaquePointer?
    private var vocab: OpaquePointer?
    /// The GGUF currently resident, so a changed selection triggers a reload
    /// instead of quietly answering from the old model.
    private var loadedPath: String?
    /// Which model that file is — prompt rendering differs between families.
    private var loadedSpec: ModelSpec?
    /// llama_backend_init/free are process-wide — pair them once, not per load.
    private var backendReady = false

    /// From the loaded model's spec; the tiers can differ in context length.
    private var contextTokens: Int32 = 8192
    // Reply length is per-call now — see GenerationOptions.maxTokens, which
    // still defaults to 1200 for chat.
    private let batchSize: Int32 = 1024

    private init() {}

    // MARK: - Model location

    /// Path of the model that will actually load — the teacher's selection,
    /// falling back past one whose file is gone.
    static func locateModelFile() -> String? {
        ModelCatalog.installedPath(for: ModelCatalog.activeSpec)
    }

    /// True if any catalog model is installed. Decides between the blocking
    /// first-run setup screen (nothing runnable — chat can't work) and the
    /// inline download card (something is usable; never block an upgrade).
    static func anyModelPresent() -> Bool { ModelCatalog.hasAnyInstalled }

    // MARK: - Loading

    /// Must be called on `queue`.
    private func ensureLoaded() throws {
        let spec = ModelCatalog.activeSpec
        guard let path = ModelCatalog.installedPath(for: spec) else {
            throw ChatBackendError.modelFileMissing
        }
        if ctx != nil, loadedPath == path { return }
        // A different model was picked (or the loaded one was deleted): drop
        // the resident weights before mapping the new file.
        unloadLocked()

        // Route llama/ggml logs to nowhere unless debugging.
        llama_log_set({ level, text, _ in
            guard ProcessInfo.processInfo.environment["TW_LLAMA_LOG"] != nil,
                  let text else { return }
            FileHandle.standardError.write(Data(String(cString: text).utf8))
        }, nil)

        if !backendReady {
            llama_backend_init()
            backendReady = true
        }
        contextTokens = spec.contextTokens
        var modelParams = llama_model_default_params()
        modelParams.n_gpu_layers = 99  // full Metal offload
        guard let model = llama_model_load_from_file(path, modelParams) else {
            throw ChatBackendError.modelLoadFailed
        }

        var ctxParams = llama_context_default_params()
        ctxParams.n_ctx = UInt32(contextTokens)
        ctxParams.n_batch = UInt32(batchSize)
        let threads = Int32(max(2, ProcessInfo.processInfo.activeProcessorCount - 2))
        ctxParams.n_threads = threads
        ctxParams.n_threads_batch = threads
        guard let ctx = llama_init_from_model(model, ctxParams) else {
            llama_model_free(model)
            throw ChatBackendError.contextCreationFailed
        }

        self.model = model
        self.ctx = ctx
        self.vocab = llama_model_get_vocab(model)
        self.loadedPath = path
        self.loadedSpec = spec
    }

    /// Frees the Metal context/model. Call before process exit — tearing the
    /// process down with a live context trips a ggml-metal assert in atexit.
    func shutdown() {
        queue.sync {
            unloadLocked()
            if backendReady {
                llama_backend_free()
                backendReady = false
            }
        }
    }

    /// Drops the resident weights, leaving the backend initialised. A model
    /// switch calls this and lets the next request load the new file; a delete
    /// calls it so llama.cpp isn't holding the GGUF being removed.
    func unload() {
        queue.sync { unloadLocked() }
    }

    /// Must be called on `queue`.
    private func unloadLocked() {
        if let ctx { llama_free(ctx) }
        if let model { llama_model_free(model) }
        ctx = nil
        model = nil
        vocab = nil
        loadedPath = nil
        loadedSpec = nil
    }

    // MARK: - Prompt formatting

    /// Renders the conversation with the model's chat template, falling back
    /// to hand-built ChatML (Qwen's native format). For models with a thinking
    /// span, the empty `<think>` block pre-fills it so replies start
    /// immediately instead of spending the token budget reasoning — a family
    /// without one (Llama) must not get it, hence the per-spec flag.
    private func renderPrompt(turns: [ChatTurn], options: GenerationOptions) -> String {
        var rendered: String
        if let model, let templated = applyModelTemplate(model: model, turns: turns) {
            rendered = templated
        } else {
            rendered = ""
            for turn in turns {
                rendered += "<|im_start|>\(turn.role.rawValue)\n\(turn.content)<|im_end|>\n"
            }
            rendered += "<|im_start|>assistant\n"
        }
        if loadedSpec?.usesThinkPrefill ?? true, !rendered.hasSuffix("</think>\n\n") {
            rendered += "<think>\n\n</think>\n\n"
        }
        if let prefix = options.assistantPrefix, !prefix.isEmpty {
            rendered += prefix
        }
        return rendered
    }

    /// Applies the GGUF's own chat template, retrying without a system turn if
    /// the template refuses one. Gemma's template has no system role, and the
    /// silent fallback below is Qwen-shaped ChatML — the wrong prompt for
    /// every other family — so it's worth folding the system text into the
    /// first user turn and asking again before giving up.
    private func applyModelTemplate(model: OpaquePointer, turns: [ChatTurn]) -> String? {
        if let rendered = renderWithTemplate(model: model, turns: turns) { return rendered }
        guard turns.contains(where: { $0.role == .system }) else { return nil }
        return renderWithTemplate(model: model, turns: foldingSystemIntoFirstUser(turns))
    }

    /// Merges any system turns into the first user turn, for templates that
    /// only accept user/assistant.
    private func foldingSystemIntoFirstUser(_ turns: [ChatTurn]) -> [ChatTurn] {
        let system = turns.filter { $0.role == .system }.map(\.content).joined(separator: "\n\n")
        var rest = turns.filter { $0.role != .system }
        guard let first = rest.first, first.role == .user else {
            return [ChatTurn(role: .user, content: system)] + rest
        }
        rest[0] = ChatTurn(role: .user, content: "\(system)\n\n\(first.content)")
        return rest
    }

    private func renderWithTemplate(model: OpaquePointer, turns: [ChatTurn]) -> String? {
        guard let tmpl = llama_model_chat_template(model, nil) else { return nil }
        var cMessages: [llama_chat_message] = turns.map {
            llama_chat_message(role: strdup($0.role.rawValue), content: strdup($0.content))
        }
        defer {
            for m in cMessages {
                free(UnsafeMutableRawPointer(mutating: m.role))
                free(UnsafeMutableRawPointer(mutating: m.content))
            }
        }
        var capacity = turns.reduce(256) { $0 + $1.content.utf8.count * 2 }
        for _ in 0..<2 {
            var buf = [CChar](repeating: 0, count: capacity)
            let written = llama_chat_apply_template(tmpl, &cMessages, cMessages.count, true, &buf, Int32(capacity))
            if written < 0 { return nil }
            if Int(written) <= capacity {
                return String(decoding: buf[0..<Int(written)].map { UInt8(bitPattern: $0) }, as: UTF8.self)
            }
            capacity = Int(written) + 1
        }
        return nil
    }

    // MARK: - Generation

    func streamReply(turns: [ChatTurn], options: GenerationOptions) -> AsyncThrowingStream<String, Error> {
        let cancelled = CancellationFlag()
        return AsyncThrowingStream { continuation in
            continuation.onTermination = { _ in cancelled.set() }
            queue.async { [self] in
                do {
                    try generate(turns: turns, options: options, cancelled: cancelled) { piece in
                        continuation.yield(piece)
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }

    /// Token count for `text` under the loaded model's vocabulary. Stages that
    /// budget their own prompts need this: the overflow rule below keeps the
    /// *tail*, so a prompt that's too long loses its system turn silently.
    func countTokens(_ text: String) throws -> Int {
        var count = 0
        var failure: Error?
        queue.sync { [self] in
            do {
                try ensureLoaded()
                guard let vocab else { throw ChatBackendError.contextCreationFailed }
                count = try tokenize(text, vocab: vocab).count
            } catch {
                failure = error
            }
        }
        if let failure { throw failure }
        return count
    }

    /// Must be called on `queue`.
    private func generate(turns: [ChatTurn], options: GenerationOptions,
                          cancelled: CancellationFlag, emit: (String) -> Void) throws {
        try ensureLoaded()
        guard let ctx, let vocab else { throw ChatBackendError.contextCreationFailed }

        let prompt = renderPrompt(turns: turns, options: options)
        var tokens = try tokenize(prompt, vocab: vocab)

        // Fresh conversation state per request (history travels in the prompt).
        llama_memory_clear(llama_get_memory(ctx), true)

        // If the prompt overflows the context, keep the tail (history is
        // oldest-first, so the recent turns survive).
        let budget = Int(contextTokens) - options.maxTokens - 16
        if tokens.count > budget {
            tokens = Array(tokens.suffix(budget))
        }

        // Decode the prompt in chunks of n_batch.
        var offset = 0
        while offset < tokens.count {
            if cancelled.isSet { return }
            let chunk = Array(tokens[offset..<min(offset + Int(batchSize), tokens.count)])
            try decode(chunk, ctx: ctx)
            offset += chunk.count
        }

        let sampler = makeSampler(options)
        defer { llama_sampler_free(sampler) }

        var utf8Buffer = Data()
        let filter = ThinkTagFilter()
        var pieceBuf = [CChar](repeating: 0, count: 512)

        // With a stop rule in play the reply can't go out token by token — the
        // trim happens at the end, and text already emitted can't be recalled.
        // Those modes are read through `complete()` anyway, which concatenates.
        let trimming = !options.stop.isEmpty || options.stopOnBalancedJSON
        var produced = options.assistantPrefix ?? ""
        if !trimming, !produced.isEmpty { emit(produced) }

        var hitStop = false
        for _ in 0..<options.maxTokens {
            if cancelled.isSet { break }
            let token = llama_sampler_sample(sampler, ctx, -1)
            if llama_vocab_is_eog(vocab, token) { break }

            let n = llama_token_to_piece(vocab, token, &pieceBuf, Int32(pieceBuf.count), 0, false)
            if n > 0 {
                pieceBuf[0..<Int(n)].withUnsafeBufferPointer { ptr in
                    ptr.baseAddress.map { utf8Buffer.append(UnsafeRawPointer($0).assumingMemoryBound(to: UInt8.self), count: Int(n)) }
                }
                if let valid = Self.extractValidUTF8Prefix(from: &utf8Buffer) {
                    if let visible = filter.push(valid), !visible.isEmpty {
                        produced += visible
                        if !trimming { emit(visible) }
                        if let cut = Self.stopIndex(in: produced, options: options) {
                            produced = String(produced.prefix(cut))
                            hitStop = true
                            break
                        }
                    }
                }
            }

            try decode([token], ctx: ctx)
        }

        // Flush whatever the filter is still holding (e.g. text that looked
        // like the start of a tag but wasn't).
        if !hitStop, let rest = filter.flush(), !rest.isEmpty {
            produced += rest
            if !trimming { emit(rest) }
        }
        if trimming {
            if let cut = Self.stopIndex(in: produced, options: options) {
                produced = String(produced.prefix(cut))
            }
            emit(produced)
        }
    }

    /// How much of `text` to keep, or nil to keep generating. Explicit stop
    /// strings win over the balanced-JSON rule when both would fire.
    static func stopIndex(in text: String, options: GenerationOptions) -> Int? {
        var cut: Int?
        for stop in options.stop where !stop.isEmpty {
            if let found = text.range(of: stop) {
                let n = text.distance(from: text.startIndex, to: found.lowerBound)
                cut = min(cut ?? n, n)
            }
        }
        if options.stopOnBalancedJSON, let n = balancedJSONEnd(text) {
            cut = min(cut ?? n, n)
        }
        return cut
    }

    /// Character count through the first complete `{…}` or `[…]`, counting
    /// only braces outside string literals so punctuation in a descriptor
    /// can't close the object early.
    static func balancedJSONEnd(_ text: String) -> Int? {
        var depth = 0
        var inString = false
        var escaped = false
        var opened = false
        for (i, ch) in text.enumerated() {
            if escaped { escaped = false; continue }
            if inString, ch == "\\" { escaped = true; continue }
            if ch == "\"" { inString.toggle(); continue }
            if inString { continue }
            if ch == "{" || ch == "[" {
                depth += 1
                opened = true
            } else if ch == "}" || ch == "]" {
                depth -= 1
                if opened, depth <= 0 { return i + 1 }
            }
        }
        return nil
    }

    private func tokenize(_ text: String, vocab: OpaquePointer) throws -> [llama_token] {
        let utf8Count = text.utf8.count
        var tokens = [llama_token](repeating: 0, count: utf8Count + 32)
        let n = llama_tokenize(vocab, text, Int32(utf8Count), &tokens, Int32(tokens.count), true, true)
        guard n >= 0 else { throw ChatBackendError.tokenizationFailed }
        return Array(tokens[0..<Int(n)])
    }

    private func decode(_ chunk: [llama_token], ctx: OpaquePointer) throws {
        // The token pointer must stay valid through llama_decode — the batch
        // struct stores it, so both calls go inside the same pointer scope.
        var mutable = chunk
        let status = mutable.withUnsafeMutableBufferPointer { ptr -> Int32 in
            let batch = llama_batch_get_one(ptr.baseAddress, Int32(ptr.count))
            return llama_decode(ctx, batch)
        }
        guard status == 0 else { throw ChatBackendError.decodeFailed }
    }

    private func makeSampler(_ options: GenerationOptions) -> UnsafeMutablePointer<llama_sampler> {
        let chain = llama_sampler_chain_init(llama_sampler_chain_default_params())!
        // Temperature 0 means "the same answer every time", which sampling
        // can't promise however low you set it — take the argmax instead.
        guard options.temperature > 0 else {
            llama_sampler_chain_add(chain, llama_sampler_init_greedy())
            return chain
        }
        // Qwen3-recommended sampling for non-thinking chat.
        llama_sampler_chain_add(chain, llama_sampler_init_top_k(options.topK))
        llama_sampler_chain_add(chain, llama_sampler_init_top_p(options.topP, 1))
        llama_sampler_chain_add(chain, llama_sampler_init_temp(options.temperature))
        llama_sampler_chain_add(chain, llama_sampler_init_dist(options.seed ?? UInt32.random(in: 0..<UInt32.max)))
        return chain
    }

    /// Removes the longest valid UTF-8 prefix from `buffer` and returns it,
    /// leaving any trailing partial multi-byte sequence for the next call.
    static func extractValidUTF8Prefix(from buffer: inout Data) -> String? {
        guard !buffer.isEmpty else { return nil }
        let bytes = [UInt8](buffer)
        var cut = bytes.count
        // Only the final (≤4-byte) sequence can be incomplete: walk back past
        // continuation bytes to the last leading byte and check its length.
        var i = bytes.count - 1
        var back = 0
        while i >= 0 && back < 4 {
            let b = bytes[i]
            if b & 0xC0 != 0x80 {  // not a continuation byte
                let needed: Int
                if b & 0x80 == 0 { needed = 1 }
                else if b & 0xE0 == 0xC0 { needed = 2 }
                else if b & 0xF0 == 0xE0 { needed = 3 }
                else if b & 0xF8 == 0xF0 { needed = 4 }
                else { needed = 1 }
                cut = (bytes.count - i) >= needed ? bytes.count : i
                break
            }
            i -= 1
            back += 1
        }
        guard cut > 0 else { return nil }
        guard let s = String(data: Data(bytes[0..<cut]), encoding: .utf8) else {
            buffer.removeFirst()  // invalid byte — drop one to resync
            return nil
        }
        buffer.removeFirst(cut)
        return s
    }
}

/// Thread-safe cancellation flag shared between the stream consumer and the
/// generation queue.
final class CancellationFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var value = false
    var isSet: Bool { lock.lock(); defer { lock.unlock() }; return value }
    func set() { lock.lock(); value = true; lock.unlock() }
}

/// Streaming filter that hides Qwen's optional `<think>…</think>` reasoning
/// span (only ever emitted at the start of a reply) from the visible output.
final class ThinkTagFilter {
    private enum State { case deciding, inThink, passthrough }
    private var state = State.deciding
    private var held = ""

    func push(_ text: String) -> String? {
        switch state {
        case .passthrough:
            return text
        case .inThink:
            held += text
            if let range = held.range(of: "</think>") {
                let after = String(held[range.upperBound...])
                held = ""
                state = .passthrough
                return after.drop(while: { $0 == "\n" || $0 == " " }).isEmpty
                    ? nil
                    : String(after.drop(while: { $0 == "\n" || $0 == " " }))
            }
            return nil
        case .deciding:
            held += text
            let trimmed = held.drop(while: { $0 == "\n" || $0 == " " })
            if trimmed.hasPrefix("<think>") {
                state = .inThink
                held = String(trimmed.dropFirst("<think>".count))
                return push("")
            }
            // Still possibly a prefix of "<think>"? Hold on.
            if "<think>".hasPrefix(trimmed) && !trimmed.isEmpty {
                return nil
            }
            state = .passthrough
            let out = held
            held = ""
            return out
        }
    }

    func flush() -> String? {
        defer { held = ""; state = .passthrough }
        switch state {
        case .deciding: return held.isEmpty ? nil : held
        default: return nil
        }
    }
}
