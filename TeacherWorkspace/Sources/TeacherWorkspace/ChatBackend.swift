import Foundation

struct ChatTurn {
    enum Role: String {
        case system, user, assistant
    }

    var role: Role
    var content: String
}

enum ChatBackendError: LocalizedError {
    case modelFileMissing
    case modelLoadFailed
    case contextCreationFailed
    case tokenizationFailed
    case decodeFailed

    var errorDescription: String? {
        switch self {
        case .modelFileMissing:
            return "The on-device model file is missing from the app bundle."
        case .modelLoadFailed:
            return "The on-device model could not be loaded."
        case .contextCreationFailed:
            return "Could not create an inference context for the on-device model."
        case .tokenizationFailed:
            return "The conversation could not be tokenized."
        case .decodeFailed:
            return "The on-device model failed while generating a reply."
        }
    }
}

/// Per-call generation controls. Chat wants warmth and room; the evaluation
/// stages want the same answer twice and a hard ceiling on how long a confused
/// model can ramble.
struct GenerationOptions {
    var temperature: Float = 0.7
    var topK: Int32 = 20
    var topP: Float = 0.8
    /// nil keeps the random-per-call seed chat has always used. A fixed seed
    /// plus temperature 0 is what makes a placement reproducible.
    var seed: UInt32?
    var maxTokens: Int = 1200
    /// Generation ends as soon as the reply contains one of these; the match
    /// and everything after it is trimmed.
    var stop: [String] = []
    /// Ends once brace depth returns to zero — for stages that want exactly
    /// one JSON object and nothing after it.
    var stopOnBalancedJSON = false
    /// Text put into the assistant's mouth before sampling begins. A model
    /// that has already "written" `{"meets":` cannot open with a preamble or
    /// wrap its answer in a code fence.
    var assistantPrefix: String?

    /// Today's behaviour, unchanged.
    static let chat = GenerationOptions()

    /// One small JSON object, reproducible.
    static let extraction = GenerationOptions(
        temperature: 0, seed: 1, maxTokens: 96, stopOnBalancedJSON: true)

    /// A single word — YES or NO.
    static let shortAnswer = GenerationOptions(
        temperature: 0, seed: 1, maxTokens: 6, stop: ["\n"])

    /// One sentence for a human to read.
    static let prose = GenerationOptions(
        temperature: 0.3, seed: 1, maxTokens: 80, stop: ["\n\n"])
}

/// A chat model that can stream a reply for a conversation. Implementations:
/// LlamaBackend (embedded llama.cpp + Qwen3.5). Cloud backends (Claude API)
/// or Apple's on-device model can be dropped in later.
protocol ChatBackend {
    func streamReply(turns: [ChatTurn], options: GenerationOptions) -> AsyncThrowingStream<String, Error>
}

extension ChatBackend {
    func streamReply(turns: [ChatTurn]) -> AsyncThrowingStream<String, Error> {
        streamReply(turns: turns, options: .chat)
    }

    /// The whole reply, once it's done. Sub-tasks want a value to parse, not a
    /// stream to render — and every call site that hand-rolled this loop got
    /// the same six lines slightly differently.
    func complete(turns: [ChatTurn], options: GenerationOptions = .chat) async throws -> String {
        var out = ""
        for try await piece in streamReply(turns: turns, options: options) { out += piece }
        return out
    }
}
