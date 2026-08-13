import Foundation

/// A local, append-only record of every request that left this Mac.
///
/// Deliberately **not** in `store.json`. That file is rewritten whole on a
/// one-second debounce and its decoder is load-bearing for the teacher's
/// chats and classroom; an audit trail must not be losable to a decode
/// failure or a half-finished write. JSONL beside it instead: one line per
/// event, appended, never rewritten.
///
/// This is the answer to "prove nothing left." Blocked attempts are logged
/// too — showing that the gate fired is as much of the answer as showing what
/// went out.
struct FrontierAuditEntry: Codable, Identifiable {
    /// Schema version, so a future reader knows what it's looking at.
    var v = 1
    var id: String
    var at: Date
    /// "attempt" · "completed" · "failed" · "blocked"
    var phase: String
    var host: String
    var path: String
    var modelId: String
    var requestBytes: Int
    var responseBytes: Int?
    /// "clean" or a count of what the gate found.
    var gateVerdict: String
    var subjectType: String?
    var subjectId: String?
    var subjectTitle: String?
    /// The full verbatim payload, on the "attempt" line only. This is the
    /// receipt — an audit log that summarises what it sent is not one.
    var payload: String?
    var error: String?
}

enum FrontierAuditLog {

    static let fileName = "frontier-audit.jsonl"

    /// Nil under every probe, for the same reason `PersistenceStore.fileURL`
    /// is: a headless run must never append to a teacher's real audit trail.
    static var fileURL: URL? {
        let env = ProcessInfo.processInfo.environment
        if let override = env["TW_AUDIT_FILE"] { return URL(fileURLWithPath: override) }
        for probe in ["TW_SNAPSHOT", "TW_PROBE", "TW_REDACT_TEST", "TW_REDACT_ADVERSARIAL",
                      "TW_REVIEW_PAYLOAD", "TW_REVIEW_PARSE", "TW_REVIEW_ERRORS"]
        where env[probe] != nil {
            return nil
        }
        guard let base = FileManager.default.urls(for: .applicationSupportDirectory,
                                                  in: .userDomainMask).first
        else { return nil }
        let dir = base.appendingPathComponent(AppInfo.supportDirectory, isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent(fileName)
    }

    private static let queue = DispatchQueue(label: "frontier.audit")

    /// Appends one line. Serialised on its own queue so two concurrent
    /// reviews can't interleave half-written JSON.
    static func append(_ entry: FrontierAuditEntry) {
        guard let url = fileURL else { return }
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        guard var data = try? encoder.encode(entry) else { return }
        data.append(0x0A)  // newline

        queue.sync {
            if let handle = try? FileHandle(forWritingTo: url) {
                defer { try? handle.close() }
                _ = try? handle.seekToEnd()
                try? handle.write(contentsOf: data)
            } else {
                try? data.write(to: url, options: .atomic)
            }
        }
    }

    static func entries() -> [FrontierAuditEntry] {
        guard let url = fileURL,
              let text = try? String(contentsOf: url, encoding: .utf8) else { return [] }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return text.split(separator: "\n").compactMap { line in
            try? decoder.decode(FrontierAuditEntry.self, from: Data(line.utf8))
        }
    }

    /// Newest first, for the viewer.
    static func recent(limit: Int = 200) -> [FrontierAuditEntry] {
        Array(entries().sorted { $0.at > $1.at }.prefix(limit))
    }

    static var sendCount: Int {
        entries().filter { $0.phase == "completed" }.count
    }

    // MARK: - Writing the two halves of a send

    /// Written **before** `URLSession` runs, carrying the full payload. A
    /// crash mid-request must not leave a send with no record.
    @discardableResult
    static func recordAttempt(payload: ReviewPayload, provider: FrontierProvider,
                              title: String) -> String {
        let id = "audit-\(UUID().uuidString)"
        append(FrontierAuditEntry(
            id: id, at: Date(), phase: "attempt",
            host: provider.host, path: "/v1/messages", modelId: provider.modelId,
            requestBytes: payload.byteCount, responseBytes: nil,
            gateVerdict: "clean",
            subjectType: payload.subjectRef.type.rawValue, subjectId: payload.subjectRef.id,
            subjectTitle: title, payload: payload.outgoingText, error: nil))
        return id
    }

    static func recordCompleted(id: String, provider: FrontierProvider,
                                requestBytes: Int, responseBytes: Int) {
        append(FrontierAuditEntry(
            id: id, at: Date(), phase: "completed",
            host: provider.host, path: "/v1/messages", modelId: provider.modelId,
            requestBytes: requestBytes, responseBytes: responseBytes,
            gateVerdict: "clean", subjectType: nil, subjectId: nil, subjectTitle: nil,
            payload: nil, error: nil))
    }

    static func recordFailed(id: String, provider: FrontierProvider,
                             requestBytes: Int, error: Error) {
        append(FrontierAuditEntry(
            id: id, at: Date(), phase: "failed",
            host: provider.host, path: "/v1/messages", modelId: provider.modelId,
            requestBytes: requestBytes, responseBytes: nil,
            gateVerdict: "clean", subjectType: nil, subjectId: nil, subjectTitle: nil,
            payload: nil, error: error.localizedDescription))
    }

    /// The gate stopped it. Logged with a count and no payload — the whole
    /// point is that these bytes never left, so writing them here would
    /// undo the block.
    static func recordBlocked(provider: FrontierProvider, findings: [RedactionGate.Finding],
                              subject: ArtifactRef?, title: String?) {
        append(FrontierAuditEntry(
            id: "audit-\(UUID().uuidString)", at: Date(), phase: "blocked",
            host: provider.host, path: "/v1/messages", modelId: provider.modelId,
            requestBytes: 0, responseBytes: nil,
            gateVerdict: "blocked: \(findings.count) finding\(findings.count == 1 ? "" : "s")",
            subjectType: subject?.type.rawValue, subjectId: subject?.id, subjectTitle: title,
            payload: nil, error: nil))
    }

    // MARK: - Export

    /// A transcript a principal or a district privacy officer can read
    /// without knowing what JSONL is.
    static func markdownTranscript() -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short

        var out = "# Off-device review log — \(AppInfo.productName)\n\n"
        out += "Every request this app has sent outside this Mac, oldest first. "
        out += "Blocked attempts are included: they show the check working.\n\n"

        let all = entries().sorted { $0.at < $1.at }
        if all.isEmpty { return out + "_Nothing has ever been sent._\n" }

        for entry in all {
            out += "## \(formatter.string(from: entry.at)) — \(entry.phase)\n\n"
            out += "- Destination: `\(entry.host)\(entry.path)`\n"
            out += "- Model: \(entry.modelId)\n"
            if let title = entry.subjectTitle { out += "- Document: \(title)\n" }
            out += "- Bytes sent: \(entry.requestBytes)\n"
            out += "- Check: \(entry.gateVerdict)\n"
            if let error = entry.error { out += "- Result: \(error)\n" }
            if let payload = entry.payload {
                out += "\n<details><summary>Exactly what was sent</summary>\n\n```\n"
                out += payload
                out += "\n```\n\n</details>\n"
            }
            out += "\n"
        }
        return out
    }
}
