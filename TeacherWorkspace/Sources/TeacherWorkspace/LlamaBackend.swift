import Foundation
import llama

/// Runs the embedded Qwen3.5 GGUF model in-process via llama.cpp (Metal).
/// The model is loaded lazily on first use and kept resident.
final class LlamaBackend: ChatBackend, @unchecked Sendable {
    static let shared = LlamaBackend()

    static let modelFileName = "Qwen3.5-2B-Q4_K_M"
    static let modelDisplayName = "Qwen3.5-2B"

    private let queue = DispatchQueue(label: "llama.generation", qos: .userInitiated)
    private var model: OpaquePointer?
    private var ctx: OpaquePointer?
    private var vocab: OpaquePointer?

    private let contextTokens: Int32 = 8192
    private let maxReplyTokens = 1200
    private let batchSize: Int32 = 1024

    private init() {}

    // MARK: - Model location

    static func locateModelFile() -> String? {
        if let bundled = Bundle.main.path(forResource: modelFileName, ofType: "gguf") {
            return bundled
        }
        // Ship-small builds download the model here on first launch.
        if let installed = ModelDownloader.installedModelPath {
            return installed
        }
        // TW_MODEL_DIR pins tests to an explicit directory — don't let the
        // dev checkout's real model leak into them.
        if ProcessInfo.processInfo.environment["TW_MODEL_DIR"] != nil { return nil }
        // Dev fallback for `swift run` / debug builds: TeacherWorkspace/Models/
        let devPath = URL(fileURLWithPath: #filePath)                     // …/Sources/TeacherWorkspace/LlamaBackend.swift
            .deletingLastPathComponent()                                  // …/Sources/TeacherWorkspace
            .deletingLastPathComponent()                                  // …/Sources
            .deletingLastPathComponent()                                  // …/TeacherWorkspace
            .appendingPathComponent("Models/\(modelFileName).gguf").path
        return FileManager.default.fileExists(atPath: devPath) ? devPath : nil
    }

    /// True if *any* GGUF exists anywhere the app looks. Decides between the
    /// blocking first-run setup screen (nothing at all — chat can't work) and
    /// the inline download card (an older model is usable; never block a
    /// future model upgrade).
    static func anyModelPresent() -> Bool {
        if locateModelFile() != nil { return true }
        let fm = FileManager.default
        func hasGGUF(_ dir: URL?) -> Bool {
            guard let dir, let items = try? fm.contentsOfDirectory(atPath: dir.path) else { return false }
            return items.contains { $0.hasSuffix(".gguf") }
        }
        return hasGGUF(Bundle.main.resourceURL) || hasGGUF(ModelDownloader.installDirectory)
    }

    // MARK: - Loading

    /// Must be called on `queue`.
    private func ensureLoaded() throws {
        if ctx != nil { return }
        guard let path = Self.locateModelFile() else { throw ChatBackendError.modelFileMissing }

        // Route llama/ggml logs to nowhere unless debugging.
        llama_log_set({ level, text, _ in
            guard ProcessInfo.processInfo.environment["TW_LLAMA_LOG"] != nil,
                  let text else { return }
            FileHandle.standardError.write(Data(String(cString: text).utf8))
        }, nil)

        llama_backend_init()
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
    }

    /// Frees the Metal context/model. Call before process exit — tearing the
    /// process down with a live context trips a ggml-metal assert in atexit.
    func shutdown() {
        queue.sync {
            if let ctx { llama_free(ctx) }
            if let model { llama_model_free(model) }
            ctx = nil
            model = nil
            vocab = nil
            llama_backend_free()
        }
    }

    // MARK: - Prompt formatting

    /// Renders the conversation with the model's chat template, falling back
    /// to hand-built ChatML (Qwen's native format). The empty `<think>` block
    /// pre-fills Qwen's reasoning span so replies start immediately instead of
    /// spending the token budget thinking.
    private func renderPrompt(turns: [ChatTurn]) -> String {
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
        if !rendered.hasSuffix("</think>\n\n") {
            rendered += "<think>\n\n</think>\n\n"
        }
        return rendered
    }

    private func applyModelTemplate(model: OpaquePointer, turns: [ChatTurn]) -> String? {
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

    func streamReply(turns: [ChatTurn]) -> AsyncThrowingStream<String, Error> {
        let cancelled = CancellationFlag()
        return AsyncThrowingStream { continuation in
            continuation.onTermination = { _ in cancelled.set() }
            queue.async { [self] in
                do {
                    try generate(turns: turns, cancelled: cancelled) { piece in
                        continuation.yield(piece)
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }

    /// Must be called on `queue`.
    private func generate(turns: [ChatTurn], cancelled: CancellationFlag, emit: (String) -> Void) throws {
        try ensureLoaded()
        guard let ctx, let vocab else { throw ChatBackendError.contextCreationFailed }

        let prompt = renderPrompt(turns: turns)
        var tokens = try tokenize(prompt, vocab: vocab)

        // Fresh conversation state per request (history travels in the prompt).
        llama_memory_clear(llama_get_memory(ctx), true)

        // If the prompt overflows the context, keep the tail (history is
        // oldest-first, so the recent turns survive).
        let budget = Int(contextTokens) - maxReplyTokens - 16
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

        let sampler = makeSampler()
        defer { llama_sampler_free(sampler) }

        var utf8Buffer = Data()
        let filter = ThinkTagFilter()
        var pieceBuf = [CChar](repeating: 0, count: 512)

        for _ in 0..<maxReplyTokens {
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
                        emit(visible)
                    }
                }
            }

            try decode([token], ctx: ctx)
        }

        // Flush whatever the filter is still holding (e.g. text that looked
        // like the start of a tag but wasn't).
        if let rest = filter.flush(), !rest.isEmpty {
            emit(rest)
        }
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

    private func makeSampler() -> UnsafeMutablePointer<llama_sampler> {
        // Qwen3-recommended sampling for non-thinking chat.
        let chain = llama_sampler_chain_init(llama_sampler_chain_default_params())!
        llama_sampler_chain_add(chain, llama_sampler_init_top_k(20))
        llama_sampler_chain_add(chain, llama_sampler_init_top_p(0.8, 1))
        llama_sampler_chain_add(chain, llama_sampler_init_temp(0.7))
        llama_sampler_chain_add(chain, llama_sampler_init_dist(UInt32.random(in: 0..<UInt32.max)))
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
