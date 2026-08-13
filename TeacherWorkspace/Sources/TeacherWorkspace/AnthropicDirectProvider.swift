import Foundation

/// The v1 provider: the teacher's own Anthropic key, straight to the API.
///
/// Swift has no official Anthropic SDK, so this is raw HTTP against
/// `/v1/messages`. Non-streaming on purpose — there is nothing to watch, a
/// spinner is honest, and it keeps the request well inside the timeout.
struct AnthropicDirectProvider: FrontierProvider {

    let id = "anthropic"
    let displayName = "Anthropic"
    let modelId = "claude-opus-5"
    let modelDisplayName = "Claude Opus 5"
    let host = "api.anthropic.com"

    static let keychainItem = Keychain.Item(
        service: "org.xqinstitute.lesson-lab.frontier", account: "anthropic")

    var credential: FrontierCredential { .userKey(Self.keychainItem) }

    var isConfigured: Bool {
        Self.storedKey() != nil
    }

    /// `TW_CLAUDE_KEY` lets a probe run without touching the real Keychain —
    /// same shape as `TW_MODEL_URL` in `ModelDownload`.
    static func storedKey() -> String? {
        if let override = ProcessInfo.processInfo.environment["TW_CLAUDE_KEY"],
           !override.isEmpty {
            return override
        }
        return Keychain.read(keychainItem)
    }

    /// Overridable for probes, so the transport can be exercised against a
    /// local echo server before it is ever pointed at the real API.
    static var endpoint: URL {
        if let override = ProcessInfo.processInfo.environment["TW_FRONTIER_URL"],
           let url = URL(string: override) {
            return url
        }
        return URL(string: "https://api.anthropic.com/v1/messages")!
    }

    private static let session: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 90
        config.timeoutIntervalForResource = 180
        // Fail fast and say so, rather than hanging while a teacher waits on
        // a network that is never coming back.
        config.waitsForConnectivity = false
        return URLSession(configuration: config)
    }()

    // MARK: - The call

    func review(_ payload: ReviewPayload, lexicon: PIILexicon) async throws -> ReviewResult {
        guard let key = Self.storedKey() else { throw FrontierError.noKey }

        var request = URLRequest(url: Self.endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "content-type")
        request.setValue(key, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        request.httpBody = try Self.body(for: payload, model: modelId)

        // The second, deliberately redundant gate run — on the exact bytes
        // `URLSession` is about to send, not on the string they were built
        // from. This is what catches a name the teacher typed back into the
        // payload after the first check passed.
        do {
            try RedactionGate.assertClean(request.httpBody ?? Data(), lexicon: lexicon)
        } catch let blocked as RedactionGate.Blocked {
            throw FrontierError.blocked(blocked.findings)
        }

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await Self.session.data(for: request)
        } catch let urlError as URLError {
            throw FrontierError.from(urlError: urlError, host: host)
        } catch is CancellationError {
            throw FrontierError.cancelled
        }

        guard let http = response as? HTTPURLResponse else { throw FrontierError.malformed }
        guard http.statusCode == 200 else {
            throw Self.error(status: http.statusCode, headers: http, body: data)
        }
        return try Self.parse(data)
    }

    // MARK: - Request body

    static func body(for payload: ReviewPayload, model: String) throws -> Data {
        let request: [String: Any] = [
            "model": model,
            // Caps thinking *and* visible output together — thinking is on by
            // default on this model, so a tight budget truncates mid-review.
            "max_tokens": 8000,
            "output_config": [
                // A critique isn't the hard end of the model's range, and the
                // bill is the teacher's.
                "effort": "medium",
                "format": ["type": "json_schema", "schema": responseSchema],
            ],
            "messages": [["role": "user", "content": payload.outgoingText]],
        ]
        // Deliberately absent: temperature, top_p, top_k — all rejected with a
        // 400 on this model. Steer with the prompt instead.
        return try JSONSerialization.data(withJSONObject: request, options: [.sortedKeys])
    }

    /// Structured output means the reply arrives already valid, so none of
    /// `ArtifactParser`'s bracket-repair machinery is needed on this path.
    /// The first call with a new schema pays a one-time compile cost.
    static let responseSchema: [String: Any] = [
        "type": "object",
        "additionalProperties": false,
        "required": ["strengths", "suggestions", "questions"],
        "properties": [
            "strengths": [
                "type": "array",
                "items": ["type": "string"],
            ],
            "suggestions": [
                "type": "array",
                "items": [
                    "type": "object",
                    "additionalProperties": false,
                    "required": ["title", "detail", "stepNumber"],
                    "properties": [
                        "title": ["type": "string"],
                        "detail": ["type": "string"],
                        // Nullable rather than omitted: strict schemas want
                        // every property in `required`.
                        "stepNumber": ["anyOf": [["type": "integer"], ["type": "null"]]],
                    ],
                ],
            ],
            "questions": [
                "type": "array",
                "items": ["type": "string"],
            ],
        ],
    ]

    // MARK: - Response

    static func parse(_ data: Data) throws -> ReviewResult {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw FrontierError.malformed
        }

        // Check the stop reason before touching `content`. A refusal comes
        // back as a perfectly successful HTTP 200 with empty or partial
        // content — indexing content[0] here would crash on it.
        let stopReason = object["stop_reason"] as? String
        if stopReason == "refusal" {
            let details = object["stop_details"] as? [String: Any]
            throw FrontierError.refused(category: details?["category"] as? String)
        }

        // Thinking blocks precede the text, and carry no text of their own by
        // default — take the text blocks and nothing else.
        let blocks = object["content"] as? [[String: Any]] ?? []
        let text = blocks
            .filter { $0["type"] as? String == "text" }
            .compactMap { $0["text"] as? String }
            .joined()

        guard !text.isEmpty else {
            throw stopReason == "max_tokens" ? FrontierError.truncated : FrontierError.malformed
        }
        guard let result = try? JSONDecoder().decode(ReviewResult.self, from: Data(text.utf8)) else {
            throw stopReason == "max_tokens" ? FrontierError.truncated : FrontierError.malformed
        }
        return result
    }

    static func error(status: Int, headers: HTTPURLResponse, body: Data) -> FrontierError {
        let object = try? JSONSerialization.jsonObject(with: body) as? [String: Any]
        let message = ((object?["error"] as? [String: Any])?["message"] as? String) ?? ""
        let lowered = message.lowercased()

        // Anthropic reports an empty balance as a 400 or 403 whose message
        // names credit or billing — worth telling apart from a bad key,
        // because the fix is completely different.
        if lowered.contains("credit") || lowered.contains("billing") { return .outOfCredit }

        switch status {
        case 401, 403:
            return .unauthorized
        case 429:
            let retryAfter = headers.value(forHTTPHeaderField: "retry-after").flatMap(Int.init)
            return .rateLimited(retryAfter: retryAfter)
        case 500, 502, 503, 529:
            return .overloaded
        default:
            return .badResponse(status: status)
        }
    }
}
