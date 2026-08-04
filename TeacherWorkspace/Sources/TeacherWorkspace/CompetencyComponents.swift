import SwiftUI

/// Small shared dashboard atoms used by the Learner Profiles / Community
/// Graph / Project Matcher screens — follows the same
/// `@EnvironmentObject var state: AppState` + `private var t: Theme` pattern
/// as `LibraryCard`.

struct AvatarBadge: View {
    @EnvironmentObject var state: AppState
    var initials: String
    var diameter: CGFloat = 54
    private var t: Theme { state.theme }

    var body: some View {
        Text(initials)
            .font(.system(size: diameter * 0.27, weight: .bold))
            .foregroundStyle(t.accent)
            .frame(width: diameter, height: diameter)
            .background(Circle().fill(t.accentSoft))
    }
}

/// Segmented student switcher shared by Learner Profiles and Project Matcher.
struct StudentPicker: View {
    @EnvironmentObject var state: AppState
    var students: [String]
    @Binding var selected: String
    private var t: Theme { state.theme }

    var body: some View {
        HStack(spacing: 4) {
            ForEach(students, id: \.self) { name in
                let isSelected = name == selected
                Button {
                    selected = name
                } label: {
                    Text(name)
                        .font(.system(size: 12.5, weight: .semibold))
                        .foregroundStyle(isSelected ? t.text : t.sub)
                        .padding(.vertical, 6)
                        .padding(.horizontal, 14)
                        .background(RoundedRectangle(cornerRadius: 7).fill(isSelected ? t.active : .clear))
                        .contentShape(RoundedRectangle(cornerRadius: 7))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(3)
        .background(RoundedRectangle(cornerRadius: 9).fill(t.side))
    }
}

/// Capsule tag — neutral by default, or tinted for gap/strength/interest/
/// category-style chips.
struct TagChip: View {
    @EnvironmentObject var state: AppState
    var label: String
    var color: Color? = nil
    private var t: Theme { state.theme }

    var body: some View {
        Text(label)
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(color ?? t.sub)
            .padding(.vertical, 4)
            .padding(.horizontal, 11)
            .background(Capsule().fill(color?.opacity(0.14) ?? t.card))
            .overlay(Capsule().stroke(color == nil ? t.border : .clear))
    }
}

/// All-caps meta label — standalone (e.g. above a chip row) or as a
/// `CompetencyTile`'s header row.
struct SectionLabel: View {
    @EnvironmentObject var state: AppState
    var text: String
    private var t: Theme { state.theme }

    var body: some View {
        Text(text)
            .font(.system(size: 11, weight: .bold))
            .kerning(0.66)
            .textCase(.uppercase)
            .foregroundStyle(t.dim)
    }
}

/// Standard card chrome + all-caps meta label, shared by the Learner
/// Profiles and Community Graph dashboards.
struct CompetencyTile<Content: View>: View {
    @EnvironmentObject var state: AppState
    var title: String
    @ViewBuilder var content: Content
    private var t: Theme { state.theme }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionLabel(text: title)
            content
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(t.card))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(t.border))
    }
}

/// Colored dot + label, used under the node-link graphs to key strong/weak
/// ties or partner categories.
struct LegendDot: View {
    @EnvironmentObject var state: AppState
    var color: Color
    var label: String
    private var t: Theme { state.theme }

    var body: some View {
        HStack(spacing: 6) {
            Circle().fill(color).frame(width: 8, height: 8)
            Text(label).font(.system(size: 11.5)).foregroundStyle(t.sub)
        }
    }
}

/// Shown in place of the Learner Profiles / Community Graph / Project
/// Matcher screens once the teacher edits their classroom — this sample
/// data is keyed to `Classroom.demo`'s roster and unit, so it steps aside
/// the same way the sample rubrics/activities/PoGs do.
struct CompetencyDemoGate: View {
    @EnvironmentObject var state: AppState
    private var t: Theme { state.theme }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("This is demo data, tied to the sample classroom.")
                .font(.system(size: 13.5, weight: .semibold))
                .foregroundStyle(t.text)
            Text("Restore the sample classroom to explore this screen — your current classroom stays saved and you can switch back anytime.")
                .font(.system(size: 13))
                .foregroundStyle(t.sub)
                .fixedSize(horizontal: false, vertical: true)
            Button {
                state.restoreDemoClassroom(returnToChat: false)
            } label: {
                Text("Restore demo data")
                    .font(.system(size: 12.5, weight: .semibold))
                    .foregroundStyle(t.accent)
            }
            .buttonStyle(.plain)
            .padding(.top, 2)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(t.card))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(t.border))
    }
}

extension MatchTagKind {
    /// Maps each tag's meaning onto the theme's 3-slot categorical palette —
    /// consistent order reused across the Matcher and Community screens.
    func color(_ t: Theme) -> Color {
        switch self {
        case .gap: return t.categorical[1]
        case .strength: return t.categorical[2]
        case .interest: return t.categorical[0]
        }
    }
}

/// A ranking number, not a status indicator — stays a single accent color;
/// magnitude is carried by the number itself, not by a good/bad hue.
struct FitScoreBadge: View {
    @EnvironmentObject var state: AppState
    var score: Int
    var emphasized: Bool = false
    private var t: Theme { state.theme }

    var body: some View {
        Text("\(score)")
            .font(.system(size: 12, weight: .bold).monospacedDigit())
            .foregroundStyle(emphasized ? Color.white : t.accent)
            .padding(.vertical, 4)
            .padding(.horizontal, 10)
            .background(Capsule().fill(emphasized ? t.accent : t.accentSoft))
    }
}

/// Labeled horizontal fill bar for the Matcher's weighted score breakdown.
struct MeterRow: View {
    @EnvironmentObject var state: AppState
    var label: String
    var weight: Double
    var score: Int
    var color: Color
    private var t: Theme { state.theme }

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack {
                // Built as a plain String (not a Text specifier interpolation)
                // so the decimal point stays "." regardless of the system
                // locale's number formatting.
                Text("\(label) ×\(String(format: "%.1f", locale: Locale(identifier: "en_US_POSIX"), weight))")
                    .font(.system(size: 13))
                    .foregroundStyle(t.text)
                Spacer()
                Text("\(score)")
                    .font(.system(size: 12).monospacedDigit())
                    .foregroundStyle(t.dim)
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(t.hover)
                    Capsule().fill(color)
                        .frame(width: geo.size.width * CGFloat(score) / 100)
                }
            }
            .frame(height: 6)
        }
    }
}
