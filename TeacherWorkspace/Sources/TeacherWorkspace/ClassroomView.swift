import SwiftUI

/// "My Classroom" — the teacher's real setup. Everything here feeds the
/// model's system prompt, the sidebar, and the welcome greeting.
struct ClassroomView: View {
    @EnvironmentObject var state: AppState
    @State private var importTargetClassId: UUID?
    private var t: Theme { state.theme }

    var body: some View {
        LibraryPage(title: "My Classroom",
                    subtitle: "Who you teach. The assistant uses this to ground every reply — it stays on this Mac.") {
            VStack(alignment: .leading, spacing: 16) {
                if state.classroom.isDemo {
                    demoBanner
                } else if state.classroom.isBlank {
                    freshBanner
                }
                teacherCard
                ForEach($state.classroom.classes) { $cls in
                    classCard($cls)
                }
                Button {
                    state.classroom.classes.append(ClassSection())
                } label: {
                    Label("Add class", systemImage: "plus")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(t.accent)
                        .padding(.vertical, 8)
                        .padding(.horizontal, 14)
                        .contentShape(RoundedRectangle(cornerRadius: 9))
                }
                .buttonStyle(.plain)
                .hoverHighlight(radius: 9, hover: t.hover, base: t.card)
                .overlay(RoundedRectangle(cornerRadius: 9, style: .continuous).stroke(t.border))
            }
        }
        .sheet(isPresented: Binding(
            get: { importTargetClassId != nil },
            set: { if !$0 { importTargetClassId = nil } }
        )) {
            if let classId = importTargetClassId {
                RosterImportSheet(classId: classId) { importTargetClassId = nil }
                    .environmentObject(state)
            }
        }
        .onChange(of: state.classroom) { old, new in
            // Any real edit makes the classroom the teacher's own; sample
            // chats and artifacts step aside. Landing exactly on the pristine
            // demo classroom is the restore path, not an edit — no hand-typed
            // change can reproduce it, so this only ever catches that.
            if new.isDemo, old != new, new != .demo {
                state.classroom.isDemo = false
                if let active = state.activeChat, SampleData.chatMeta[active] != nil {
                    state.activeChat = nil
                }
            }
        }
    }

    private var demoBanner: some View {
        HStack(spacing: 10) {
            Image(systemName: "sparkles")
                .foregroundStyle(t.accent)
            Text("This is demo data. Edit anything to make it yours — the sample chats and library items will step aside.")
                .font(.system(size: 12.5))
                .foregroundStyle(t.sub)
            Spacer()
            Button {
                state.startFreshClassroom()
            } label: {
                Text("Start fresh")
                    .font(.system(size: 12.5, weight: .semibold))
                    .foregroundStyle(t.accent)
            }
            .buttonStyle(.plain)
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(t.accentSoft))
    }

    /// Counterpart to the demo banner: once the classroom is empty, offer the
    /// sample data back, so "Start fresh" isn't a one-way door.
    private var freshBanner: some View {
        HStack(spacing: 10) {
            Image(systemName: "person.crop.circle.badge.plus")
                .foregroundStyle(t.accent)
            Text("Empty classroom. Add your teacher details and classes below — or put the sample data back to explore first.")
                .font(.system(size: 12.5))
                .foregroundStyle(t.sub)
            Spacer()
            Button {
                state.restoreDemoClassroom(returnToChat: false)
            } label: {
                Text("Restore demo data")
                    .font(.system(size: 12.5, weight: .semibold))
                    .foregroundStyle(t.accent)
            }
            .buttonStyle(.plain)
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(t.accentSoft))
    }

    private var teacherCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionLabel("TEACHER")
            HStack(spacing: 10) {
                field("Your name", text: $state.classroom.teacherName)
                field("School", text: $state.classroom.school)
                field("Subject", text: $state.classroom.subject)
            }
        }
        .padding(16)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(t.card))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(t.border))
    }

    private func classCard(_ cls: Binding<ClassSection>) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                sectionLabel("CLASS")
                Spacer()
                Button {
                    state.classroom.classes.removeAll { $0.id == cls.wrappedValue.id }
                } label: {
                    Image(systemName: "trash")
                        .font(.system(size: 11))
                        .foregroundStyle(t.dim)
                        .frame(width: 26, height: 26)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .hoverHighlight(radius: 6, hover: t.hover)
                .help("Remove class")
            }
            HStack(spacing: 10) {
                field("Name (e.g. Period 2 · Biology)", text: cls.name)
                field("Grade level", text: cls.gradeLevel).frame(maxWidth: 160)
            }
            field("Notes for the assistant (current unit, priorities…)", text: cls.notes)

            sectionLabel("STUDENTS")
                .padding(.top, 4)
            ForEach(cls.students) { $student in
                HStack(spacing: 8) {
                    field("Name", text: $student.name).frame(maxWidth: 180)
                    field("Notes (strengths, growth areas, accommodations…)", text: $student.notes)
                    Button {
                        cls.wrappedValue.students.removeAll { $0.id == student.id }
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(t.dim)
                            .frame(width: 24, height: 24)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .hoverHighlight(radius: 6, hover: t.hover)
                }
            }
            HStack(spacing: 16) {
                Button {
                    cls.wrappedValue.students.append(Student())
                } label: {
                    Label("Add student", systemImage: "plus")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(t.accent)
                }
                .buttonStyle(.plain)
                Button {
                    importTargetClassId = cls.wrappedValue.id
                } label: {
                    Label("Import roster…", systemImage: "square.and.arrow.down")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(t.accent)
                }
                .buttonStyle(.plain)
                .help("Paste names or import a CSV export from your SIS")
            }
            .padding(.top, 2)
        }
        .padding(16)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(t.card))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(t.border))
    }

    private func sectionLabel(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 11, weight: .bold))
            .kerning(0.66)
            .foregroundStyle(t.dim)
    }

    private func field(_ placeholder: String, text: Binding<String>) -> some View {
        TextField(placeholder, text: text)
            .textFieldStyle(.plain)
            .font(.system(size: 13))
            .foregroundStyle(t.text)
            .padding(.vertical, 7)
            .padding(.horizontal, 10)
            .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(t.input))
            .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).stroke(t.border))
    }
}
