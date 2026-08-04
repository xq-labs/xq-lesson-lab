import Foundation

/// Parses pasted text or CSV/TSV exports from any SIS into students.
/// Handles: one name per line, comma lists, quoted CSV, "Last, First" order,
/// header rows with name / first+last / notes-like columns.
enum RosterImport {

    static func parse(_ raw: String) -> [Student] {
        let text = raw.replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
        let lines = text.split(separator: "\n").map(String.init)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        guard !lines.isEmpty else { return [] }

        let delimiter: Character = lines[0].contains("\t") ? "\t" : ","
        let rows = lines.map { splitRecord($0, delimiter: delimiter) }

        // Header detection on the first row.
        var nameCol: Int? = nil
        var firstCol: Int? = nil
        var lastCol: Int? = nil
        var notesCol: Int? = nil
        var dataRows = rows
        if let header = rows.first {
            let lowered = header.map { $0.lowercased().trimmingCharacters(in: .whitespaces) }
            for (i, h) in lowered.enumerated() {
                switch true {
                case h.contains("first") && h.contains("name"), h == "first":
                    firstCol = i
                case h.contains("last") && h.contains("name"), h == "last":
                    lastCol = i
                case h.contains("name") || h.contains("student"):
                    if nameCol == nil { nameCol = i }
                case h.contains("note") || h.contains("comment") || h.contains("accommodation") || h.contains("iep"):
                    if notesCol == nil { notesCol = i }
                default: break
                }
            }
            if nameCol != nil || (firstCol != nil && lastCol != nil) {
                dataRows = Array(rows.dropFirst())
            } else {
                nameCol = nil; firstCol = nil; lastCol = nil; notesCol = nil
            }
        }

        // Headerless "Last, First" rows split into two fields by the comma.
        // A second field that looks like a single given name (one capitalized
        // word, not an acronym like "ELL", no digits) means a reversed name
        // pair rather than name + notes.
        func isGivenNameToken(_ s: String) -> Bool {
            guard !s.isEmpty, !s.contains(" "),
                  s.rangeOfCharacter(from: .decimalDigits) == nil,
                  let first = s.first, first.isUppercase else { return false }
            let isAllCaps = s == s.uppercased() && s.count <= 4
            return !isAllCaps
        }

        var students: [Student] = []
        if nameCol == nil, firstCol == nil {
            for row in dataRows where row.count == 2 && isGivenNameToken(row[1]) && !row[0].contains(" ") {
                students.append(Student(name: "\(row[1]) \(row[0])"))
            }
            if students.count == dataRows.filter({ $0.count == 2 }).count, !students.isEmpty {
                // All two-field rows were name pairs — handle the rest as plain names.
                for row in dataRows where row.count != 2 {
                    let name = normalizeName(row.joined(separator: " "))
                    if !name.isEmpty, name.rangeOfCharacter(from: .letters) != nil {
                        students.append(Student(name: name))
                    }
                }
                return students
            }
            students = []
        }
        for row in dataRows {
            guard !row.isEmpty else { continue }
            var name = ""
            var notes = ""
            if let f = firstCol, let l = lastCol, max(f, l) < row.count {
                name = "\(row[f].trimmingCharacters(in: .whitespaces)) \(row[l].trimmingCharacters(in: .whitespaces))"
                    .trimmingCharacters(in: .whitespaces)
            } else if let n = nameCol, n < row.count {
                name = normalizeName(row[n])
            } else {
                name = normalizeName(row[0])
                // Headerless two-column exports: second column becomes notes.
                if row.count > 1 {
                    notes = row[1...].joined(separator: " · ").trimmingCharacters(in: .whitespaces)
                }
            }
            if let nc = notesCol, nc < row.count {
                notes = row[nc].trimmingCharacters(in: .whitespaces)
            }
            guard !name.isEmpty, name.rangeOfCharacter(from: .letters) != nil else { continue }
            students.append(Student(name: name, notes: notes))
        }
        return students
    }

    /// "Doe, Jane" → "Jane Doe"; otherwise cleans whitespace.
    static func normalizeName(_ raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespaces)
        let parts = trimmed.split(separator: ",", maxSplits: 1).map {
            $0.trimmingCharacters(in: .whitespaces)
        }
        if parts.count == 2, !parts[0].isEmpty, !parts[1].isEmpty,
           !parts[1].contains(" ") || parts[1].split(separator: " ").count <= 2 {
            return "\(parts[1]) \(parts[0])"
        }
        return trimmed
    }

    /// Quoted-CSV field splitter for one record. Lives in `CSV` now, shared
    /// with the competency framework importer — rosters inherit its fix for
    /// doubled quotes for free.
    static func splitRecord(_ line: String, delimiter: Character) -> [String] {
        CSV.splitRecord(line, delimiter: delimiter)
    }
}
