import Foundation

/// Reading delimited text — shared by roster import and the competency
/// framework, which want the same splitter and nothing else in common.
enum CSV {
    /// Splits one record into fields, honouring quoted sections.
    ///
    /// Handles the RFC-4180 escape: inside a quoted field, `""` is a literal
    /// quote rather than the end of the field. The previous implementation
    /// iterated without lookahead and so swallowed both characters, which
    /// silently corrupted any cell containing quoted speech.
    static func splitRecord(_ line: String, delimiter: Character) -> [String] {
        var fields: [String] = []
        var current = ""
        var inQuotes = false
        let chars = Array(line)
        var i = 0
        while i < chars.count {
            let ch = chars[i]
            if inQuotes {
                if ch == "\"" {
                    if i + 1 < chars.count, chars[i + 1] == "\"" {
                        current.append("\"")
                        i += 1
                    } else {
                        inQuotes = false
                    }
                } else {
                    current.append(ch)
                }
            } else if ch == "\"" {
                inQuotes = true
            } else if ch == delimiter {
                fields.append(current)
                current = ""
            } else {
                current.append(ch)
            }
            i += 1
        }
        fields.append(current)
        return fields.map { $0.trimmingCharacters(in: .whitespaces) }
    }

    /// Normalizes line endings and drops blank lines, the preamble every
    /// caller here wants before splitting records.
    static func lines(of raw: String) -> [String] {
        raw.replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map(String.init)
            .filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
    }
}

/// A header-mapped table. Columns are read **by name** — a file that gains or
/// reorders a column keeps working, and a file that loses one says so instead
/// of returning a neighbour's contents.
struct CSVTable {
    let headers: [String]
    let rows: [[String]]
    /// Rows whose field count didn't match the header. They're dropped rather
    /// than padded, because the likeliest cause is a cell containing a line
    /// break — which this splitter cannot represent, and which would otherwise
    /// produce plausible-looking nonsense.
    let malformedRowCount: Int

    /// Returns nil when a required column is absent, so a schema change fails
    /// at load rather than at the point some screen reads an empty string.
    init?(text: String, delimiter: Character = ",", requiring required: [String] = []) {
        let all = CSV.lines(of: text)
        guard let headerLine = all.first else { return nil }
        // A UTF-8 BOM rides in front of the first header on plenty of exports.
        let cleanedHeader = headerLine.hasPrefix("\u{FEFF}") ? String(headerLine.dropFirst()) : headerLine
        headers = CSV.splitRecord(cleanedHeader, delimiter: delimiter)
            .map { $0.lowercased().trimmingCharacters(in: .whitespaces) }
        for name in required where !headers.contains(name) { return nil }

        var kept: [[String]] = []
        var malformed = 0
        for line in all.dropFirst() {
            let fields = CSV.splitRecord(line, delimiter: delimiter)
            if fields.count == headers.count { kept.append(fields) } else { malformed += 1 }
        }
        rows = kept
        malformedRowCount = malformed
    }

    /// The value in `column`, or "" when the column doesn't exist.
    func value(_ row: [String], _ column: String) -> String {
        guard let i = headers.firstIndex(of: column), i < row.count else { return "" }
        return row[i]
    }
}
