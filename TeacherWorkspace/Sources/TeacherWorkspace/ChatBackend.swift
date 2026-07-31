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

/// A chat model that can stream a reply for a conversation. Implementations:
/// LlamaBackend (embedded llama.cpp + Qwen3.5). Cloud backends (Claude API)
/// or Apple's on-device model can be dropped in later.
protocol ChatBackend {
    func streamReply(turns: [ChatTurn]) -> AsyncThrowingStream<String, Error>
}
