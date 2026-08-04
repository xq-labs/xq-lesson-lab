import Foundation

/// Getting a dictionary out of what a 2B model actually emits, as opposed to
/// what it was asked for.
///
/// Lifted out of `ArtifactParser`, where it grew up parsing artifact blocks —
/// it never knew anything about artifacts, and the evaluation stages need the
/// same forgiveness for their own small schemas.
enum JSONRepair {
    /// Small models routinely emit slightly-broken JSON: truncated closers
    /// (`…"]}` missing a `}`) or surplus ones (`…}]}}`). Parse as-is first; on
    /// failure, walk the text string-aware and either cut at the point where
    /// the top-level object closes (drops trailing garbage) or append the
    /// missing closers (repairs truncation).
    static func object(from text: String) -> [String: Any]? {
        func parse(_ s: String) -> [String: Any]? {
            try? JSONSerialization.jsonObject(with: Data(s.utf8)) as? [String: Any]
        }
        if let obj = parse(text) { return obj }

        var stack: [Character] = []
        var inString = false
        var escaped = false
        for (offset, ch) in text.enumerated() {
            if escaped { escaped = false; continue }
            if inString {
                if ch == "\\" { escaped = true }
                else if ch == "\"" { inString = false }
                continue
            }
            switch ch {
            case "\"": inString = true
            case "{": stack.append("}")
            case "[": stack.append("]")
            case "}", "]":
                if stack.last == ch {
                    stack.removeLast()
                    if stack.isEmpty {
                        // Top-level value complete — ignore anything after it.
                        let end = text.index(text.startIndex, offsetBy: offset)
                        return parse(String(text[...end]))
                    }
                }
            default: break
            }
        }

        // Never closed — repair the truncation.
        var repaired = text
        if inString { repaired += "\"" }
        while let last = repaired.last, last == "," || last == "\n" || last == " " {
            repaired.removeLast()
        }
        repaired += String(stack.reversed())
        return parse(repaired)
    }
}
