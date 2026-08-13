import Foundation

/// Getting a dictionary out of what a 2B model actually emits, as opposed to
/// what it was asked for.
///
/// Lifted out of `ArtifactParser`, where it grew up parsing artifact blocks —
/// it never knew anything about artifacts, and the evaluation stages need the
/// same forgiveness for their own small schemas.
enum JSONRepair {
    /// Small models routinely emit slightly-broken JSON: truncated closers
    /// (`…"]}` missing a `}`), surplus ones (`…}]}}`), or — Gemma's habit — a
    /// closer skipped in the *middle* (`…"]}` then `}` with the criteria
    /// array never closed). Parse as-is first; on failure, rebuild the text
    /// string-aware with a bracket stack: insert the closers the model
    /// skipped, drop closers that match nothing, cut at the top-level close
    /// (trailing garbage), and append whatever is still open at the end
    /// (truncation).
    static func object(from text: String) -> [String: Any]? {
        func parse(_ s: String) -> [String: Any]? {
            try? JSONSerialization.jsonObject(with: Data(s.utf8)) as? [String: Any]
        }
        if let obj = parse(text) { return obj }

        // A trailing comma before a closer is invalid JSON; shave it (and any
        // whitespace) whenever a closer is about to land.
        func trimBeforeCloser(_ s: inout String) {
            while let last = s.last, last == " " || last == "\n" || last == "\t" || last == "," {
                s.removeLast()
            }
        }

        var out = ""
        var stack: [Character] = []
        var inString = false
        var escaped = false
        for ch in text {
            if escaped { escaped = false; out.append(ch); continue }
            if inString {
                if ch == "\\" { escaped = true } else if ch == "\"" { inString = false }
                out.append(ch)
                continue
            }
            switch ch {
            case "\"":
                inString = true
                out.append(ch)
            case "{":
                stack.append("}")
                out.append(ch)
            case "[":
                stack.append("]")
                out.append(ch)
            case "}", "]":
                // A closer that matches nothing open is surplus — drop it.
                guard stack.contains(ch) else { continue }
                // A closer that matches something deeper means the model
                // skipped the ones in between — insert them.
                while let expected = stack.last, expected != ch {
                    trimBeforeCloser(&out)
                    out.append(expected)
                    stack.removeLast()
                }
                stack.removeLast()
                trimBeforeCloser(&out)
                out.append(ch)
                if stack.isEmpty {
                    // Top-level value complete — ignore anything after it.
                    return parse(out)
                }
            default:
                out.append(ch)
            }
        }

        // Never closed — repair the truncation.
        if inString { out += "\"" }
        trimBeforeCloser(&out)
        out += String(stack.reversed())
        return parse(out)
    }
}
