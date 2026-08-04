import SwiftUI

/// A per-student competency dashboard — growth, confidence, peer network,
/// engagement, observed patterns, and next-lesson suggestions, assembled
/// from the same demo roster as My Classroom.
struct LearnerProfileView: View {
    @EnvironmentObject var state: AppState
    private var t: Theme { state.theme }

    var body: some View {
        LibraryPage(title: "Learner Profiles",
                    subtitle: "A live competency record for each student, assembled from real classwork — not a fixed trait, a running picture.",
                    maxWidth: 1040) {
            VStack(alignment: .leading, spacing: 16) {
                if !state.classroom.isDemo {
                    CompetencyDemoGate()
                } else if let profile = SampleData.learnerProfiles[state.selectedCompetencyStudent] {
                    StudentPicker(students: SampleData.competencyStudents, selected: $state.selectedCompetencyStudent)
                    header(profile)
                    HStack(alignment: .top, spacing: 14) {
                        CompetencyTile(title: "Competency growth") {
                            DonutRingChart(scores: profile.scores, theme: t)
                        }
                        .frame(maxWidth: .infinity)
                        CompetencyTile(title: "Confidence trend") {
                            confidenceTrend(profile)
                        }
                        .frame(maxWidth: .infinity)
                    }
                    CompetencyTile(title: "Collaboration network") {
                        collaborationNetwork(profile)
                    }
                    CompetencyTile(title: "Engagement · 12 weeks") {
                        engagement(profile)
                    }
                    CompetencyTile(title: "Patterns in \(profile.studentName.firstWord)’s evidence · observations, not labels") {
                        VStack(alignment: .leading, spacing: 8) {
                            ForEach(profile.evidenceNotes) { note in
                                noteBlock(lead: note.lead, body: note.body)
                            }
                        }
                    }
                    CompetencyTile(title: "For tomorrow’s lesson") {
                        HStack(alignment: .top, spacing: 10) {
                            ForEach(profile.lessonSuggestions) { s in
                                suggestionCard(s).frame(maxWidth: .infinity)
                            }
                        }
                    }
                } else {
                    Text("No competency data yet for this student.")
                        .font(.system(size: 13))
                        .foregroundStyle(t.dim)
                        .padding(.top, 8)
                }
            }
        }
    }

    // MARK: - Sections

    private func header(_ p: LearnerCompetencyProfile) -> some View {
        HStack(alignment: .top, spacing: 14) {
            AvatarBadge(initials: p.initials)
            VStack(alignment: .leading, spacing: 4) {
                Text(p.studentName)
                    .font(.system(size: 22, weight: .bold))
                    .kerning(-0.2)
                Text(p.gradeLabel)
                    .font(.system(size: 13.5))
                    .foregroundStyle(t.sub)
                HStack(spacing: 6) {
                    ForEach(Array(p.tags.enumerated()), id: \.offset) { idx, tag in
                        TagChip(label: tag, color: t.categorical[idx % t.categorical.count])
                    }
                }
                .padding(.top, 2)
            }
            Spacer(minLength: 0)
        }
    }

    private func confidenceTrend(_ p: LearnerCompetencyProfile) -> some View {
        let delta = (p.confidenceTrend.last?.value ?? 0) - (p.confidenceTrend.first?.value ?? 0)
        return VStack(alignment: .leading, spacing: 10) {
            Text(String(format: "%+d this term", delta))
                .font(.system(size: 26, weight: .bold))
                .kerning(-0.3)
            Sparkline(points: p.confidenceTrend, color: t.accent, theme: t)
                .frame(height: 64)
            Text(p.confidenceCaption)
                .font(.system(size: 12.5))
                .foregroundStyle(t.dim)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func collaborationNetwork(_ p: LearnerCompetencyProfile) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            NodeLinkGraph(
                centerLabel: p.initials,
                centerSublabel: nil,
                nodes: p.peerTies.map { tie in
                    GraphNode(label: tie.peerName, color: tie.isStrong ? t.accent : t.dim, strength: tie.strength)
                },
                theme: t)
                .frame(height: 240)
            HStack(spacing: 16) {
                LegendDot(color: t.accent, label: "Strong tie")
                LegendDot(color: t.dim, label: "Weak tie")
            }
        }
    }

    private func engagement(_ p: LearnerCompetencyProfile) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            WeeklyBarChart(weeks: p.engagement, color: t.accent)
                .frame(height: 92)
            Text(p.engagementCaption)
                .font(.system(size: 12.5))
                .foregroundStyle(t.dim)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func noteBlock(lead: String, body: String) -> some View {
        (Text(lead + " ").font(.system(size: 13, weight: .semibold)).foregroundStyle(t.text)
            + Text(body).font(.system(size: 13)).foregroundStyle(t.sub))
            .lineSpacing(3)
            .fixedSize(horizontal: false, vertical: true)
            .padding(11)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(t.hover))
    }

    private func suggestionCard(_ s: LessonSuggestion) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            TagChip(label: s.kind.rawValue, color: color(for: s.kind))
            Text(s.text)
                .font(.system(size: 13))
                .foregroundStyle(t.text)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(t.card))
        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).stroke(t.border))
    }

    private func color(for kind: LessonSuggestionKind) -> Color {
        switch kind {
        case .grouping: return t.categorical[0]
        case .entryPoint: return t.categorical[2]
        case .stretch: return t.categorical[1]
        }
    }

}
