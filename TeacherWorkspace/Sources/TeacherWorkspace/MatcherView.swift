import SwiftUI

/// Ranks opportunities for a student against what their competency profile
/// is missing, not just what they already like — and shows the reasoning,
/// including why the lowest-ranked match scored low.
struct MatcherView: View {
    @EnvironmentObject var state: AppState
    private var t: Theme { state.theme }

    var body: some View {
        LibraryPage(title: "Project & Mentor Matcher",
                    subtitle: "Ranks real opportunities against what a student's portfolio is missing.",
                    maxWidth: 1040) {
            VStack(alignment: .leading, spacing: 16) {
                StudentPicker(students: SampleData.competencyStudents, selected: $state.selectedCompetencyStudent)
                if let profile = SampleData.matcherProfiles[state.selectedCompetencyStudent] {
                    header(profile)
                    matchingForTile(profile)
                    VStack(spacing: 12) {
                        ForEach(Array(profile.matches.enumerated()), id: \.element.id) { idx, match in
                            if idx == 0 {
                                expandedCard(match)
                            } else {
                                collapsedCard(match, isLowest: idx == profile.matches.count - 1)
                            }
                        }
                    }
                    actionRow
                } else {
                    Text("No matches yet for this student.")
                        .font(.system(size: 13))
                        .foregroundStyle(t.dim)
                        .padding(.top, 8)
                }
            }
        }
    }

    // MARK: - Sections

    private func header(_ p: MatcherProfile) -> some View {
        HStack(spacing: 14) {
            AvatarBadge(initials: p.initials, diameter: 46)
            VStack(alignment: .leading, spacing: 2) {
                Text("Three matches for \(p.studentName.firstWord)")
                    .font(.system(size: 20, weight: .semibold))
                    .kerning(-0.2)
                Text("Ranked by what the portfolio is missing, not by what already goes well.")
                    .font(.system(size: 13.5))
                    .foregroundStyle(t.sub)
            }
        }
    }

    private func matchingForTile(_ p: MatcherProfile) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionLabel(text: "WHAT WE’RE MATCHING FOR")
            HStack(spacing: 6) {
                ForEach(p.matchingTags) { tag in
                    TagChip(label: tag.label, color: tag.kind.color(t))
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(t.hover))
    }

    private func expandedCard(_ m: MatchCandidate) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 10) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(m.orgName).font(.system(size: 15, weight: .semibold)).foregroundStyle(t.text)
                    Text(m.contactName).font(.system(size: 12.5)).foregroundStyle(t.dim)
                }
                Spacer(minLength: 8)
                VStack(alignment: .trailing, spacing: 3) {
                    Text("Best fit")
                        .font(.system(size: 10.5, weight: .semibold))
                        .foregroundStyle(t.accent)
                    FitScoreBadge(score: m.fitScore, emphasized: true)
                }
            }
            if let breakdown = m.breakdown {
                VStack(alignment: .leading, spacing: 10) {
                    SectionLabel(text: "HOW THE SCORE IS BUILT")
                    ForEach(breakdown) { item in
                        MeterRow(label: item.label, weight: item.weight, score: item.rawScore, color: t.accent)
                    }
                }
            }
            if let detail = m.detail {
                VStack(alignment: .leading, spacing: 6) {
                    detailRow("Commitment", detail.commitment)
                    detailRow("Format", detail.format)
                    detailRow("Vetting", detail.vetting, valueColor: t.categorical[2])
                    detailRow("Bonus", detail.bonus, valueColor: t.categorical[0])
                }
            }
            if let intro = m.draftIntroNote {
                VStack(alignment: .leading, spacing: 5) {
                    Text("DRAFT INTRODUCTION · EDIT BEFORE SENDING")
                        .font(.system(size: 10.5, weight: .bold))
                        .kerning(0.5)
                        .foregroundStyle(t.dim)
                    Text(intro)
                        .font(.system(size: 13))
                        .foregroundStyle(t.sub)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(11)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(t.hover))
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(t.card))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(t.accent, lineWidth: 2))
    }

    private func collapsedCard(_ m: MatchCandidate, isLowest: Bool) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 10) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(m.orgName).font(.system(size: 14, weight: .semibold)).foregroundStyle(t.text)
                    Text(m.contactName).font(.system(size: 12)).foregroundStyle(t.dim)
                }
                Spacer(minLength: 8)
                FitScoreBadge(score: m.fitScore)
            }
            Text(m.blurb)
                .font(.system(size: 13))
                .foregroundStyle(t.sub)
                .fixedSize(horizontal: false, vertical: true)
            if isLowest, let reason = m.lowRankReason {
                Text(reason)
                    .font(.system(size: 12.5))
                    .foregroundStyle(t.dim)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(t.hover))
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(t.card))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(t.border))
    }

    /// Visual only, matching the mockup's non-functional action row — this is
    /// a demo pass with no advisor system or messaging backend to call.
    private var actionRow: some View {
        HStack(spacing: 8) {
            actionButton("Send to advisor", primary: true)
            actionButton("Revise message", primary: false)
            actionButton("None of these fit", primary: false)
        }
    }

    private func actionButton(_ label: String, primary: Bool) -> some View {
        Text(label)
            .font(.system(size: 13, weight: .medium))
            .foregroundStyle(primary ? Color.white : t.text)
            .padding(.vertical, 7)
            .padding(.horizontal, 15)
            .background(Capsule().fill(primary ? t.accent : t.card))
            .overlay(Capsule().stroke(primary ? .clear : t.border))
    }

    private func detailRow(_ label: String, _ value: String, valueColor: Color? = nil) -> some View {
        HStack {
            Text(label).font(.system(size: 13)).foregroundStyle(t.sub)
            Spacer()
            Text(value).font(.system(size: 13)).foregroundStyle(valueColor ?? t.text)
        }
    }

}
