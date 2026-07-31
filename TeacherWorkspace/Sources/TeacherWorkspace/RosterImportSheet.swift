import SwiftUI
import UniformTypeIdentifiers

/// Paste-or-file roster importer for one class.
struct RosterImportSheet: View {
    @EnvironmentObject var state: AppState
    var classId: UUID
    var dismiss: () -> Void

    @State private var text = ""
    private var t: Theme { state.theme }

    private var parsed: [Student] { RosterImport.parse(text) }
    private var existingNames: Set<String> {
        Set(state.classroom.classes.first(where: { $0.id == classId })?
            .students.map { $0.name.lowercased() } ?? [])
    }
    private var newStudents: [Student] {
        parsed.filter { !existingNames.contains($0.name.lowercased()) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Import roster")
                .font(.system(size: 16, weight: .bold))
            Text("Paste student names (one per line, \"Last, First\" is fine) or open a CSV export from your SIS — PowerSchool, Infinite Campus, Google Classroom, anything. Columns named name / first / last / notes are recognized.")
                .font(.system(size: 12))
                .foregroundStyle(t.sub)
                .fixedSize(horizontal: false, vertical: true)

            TextEditor(text: $text)
                .font(.system(size: 12.5, design: .monospaced))
                .scrollContentBackground(.hidden)
                .padding(8)
                .frame(minHeight: 180)
                .background(RoundedRectangle(cornerRadius: 8).fill(t.input))
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(t.border))

            HStack {
                Button {
                    openFile()
                } label: {
                    Label("Open CSV file…", systemImage: "folder")
                        .font(.system(size: 12.5, weight: .semibold))
                }
                Spacer()
                if !text.isEmpty {
                    Text(summaryLine)
                        .font(.system(size: 12))
                        .foregroundStyle(t.sub)
                }
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Import") {
                    importStudents()
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(newStudents.isEmpty)
            }
        }
        .padding(20)
        .frame(width: 560)
        .background(t.card)
    }

    private var summaryLine: String {
        let dupes = parsed.count - newStudents.count
        var s = "\(newStudents.count) student\(newStudents.count == 1 ? "" : "s") found"
        if dupes > 0 { s += " (\(dupes) already in class)" }
        return s
    }

    private func importStudents() {
        guard let idx = state.classroom.classes.firstIndex(where: { $0.id == classId }) else { return }
        state.classroom.classes[idx].students.append(contentsOf: newStudents)
        state.classroom.isDemo = false
    }

    private func openFile() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.commaSeparatedText, .tabSeparatedText, .plainText, .utf8PlainText]
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url,
              let contents = try? String(contentsOf: url, encoding: .utf8) else { return }
        text = contents
    }
}
