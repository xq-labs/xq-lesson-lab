import SwiftUI

/// Partner organizations around a class/unit, scored for fit and capacity.
/// Scoped to Period 4 · Env. Science — the demo classroom's one unit with a
/// concrete community-partnership hook (the wetlands field trip).
struct CommunityGraphView: View {
    @EnvironmentObject var state: AppState
    private var t: Theme { state.theme }
    private let data = SampleData.communityGraph

    var body: some View {
        LibraryPage(title: "Community Opportunity Graph",
                    subtitle: "The organizations around a unit, scored for fit and capacity.",
                    maxWidth: 1040) {
            VStack(alignment: .leading, spacing: 16) {
                if !state.classroom.isDemo {
                    CompetencyDemoGate()
                } else {
                    header
                    filterRow
                    CompetencyTile(title: "Partnership network") { networkSection }
                    SectionLabel(text: "RECOMMENDED FOR THIS UNIT")
                    VStack(spacing: 11) {
                        ForEach(Array(data.recommended.enumerated()), id: \.element.id) { idx, org in
                            partnerCard(org, emphasized: idx == 0)
                        }
                    }
                    statRow
                }
            }
        }
    }

    // MARK: - Sections

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(data.unitName)
                .font(.system(size: 19, weight: .semibold))
                .kerning(-0.2)
            Text("\(data.orgCountLabel) · \(data.capacityLabel)")
                .font(.system(size: 13.5))
                .foregroundStyle(t.sub)
        }
    }

    private var filterRow: some View {
        HStack(spacing: 6) {
            filterChip("All types", active: true)
            filterChip("Under 15 mi", active: false)
            filterChip("Vetted only", active: false)
        }
    }

    private var networkSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            NodeLinkGraph(
                centerLabel: "Env. Science",
                centerSublabel: "Period 4",
                nodes: data.nodes.map { node in
                    GraphNode(label: node.name, color: color(for: node.category), strength: node.strength)
                },
                theme: t)
                .frame(height: 280)
            HStack(spacing: 14) {
                ForEach(PartnerCategory.allCases, id: \.self) { cat in
                    LegendDot(color: color(for: cat), label: cat.rawValue)
                }
            }
        }
    }

    private var statRow: some View {
        HStack(spacing: 14) {
            ForEach(data.stats) { stat in
                VStack(alignment: .leading, spacing: 6) {
                    Text(stat.label)
                        .font(.system(size: 11, weight: .bold))
                        .kerning(0.5)
                        .textCase(.uppercase)
                        .foregroundStyle(t.dim)
                    Text(stat.value)
                        .font(.system(size: 28, weight: .semibold))
                        .kerning(-0.3)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(16)
                .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(t.hover))
            }
        }
    }

    // MARK: - Pieces

    private func partnerCard(_ org: PartnerOrg, emphasized: Bool) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(alignment: .top, spacing: 10) {
                Text(org.name)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(t.text)
                Spacer(minLength: 8)
                FitScoreBadge(score: org.fitScore, emphasized: emphasized)
            }
            Text(org.blurb)
                .font(.system(size: 13))
                .foregroundStyle(t.sub)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 6) {
                ForEach(org.tags, id: \.self) { tag in
                    TagChip(label: tag)
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(t.card))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
            .stroke(emphasized ? t.accent : t.border, lineWidth: emphasized ? 2 : 1))
    }

    private func filterChip(_ label: String, active: Bool) -> some View {
        Text(label)
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(active ? t.text : t.sub)
            .padding(.vertical, 5)
            .padding(.horizontal, 12)
            .background(Capsule().fill(active ? t.active : t.card))
            .overlay(Capsule().stroke(t.border))
    }

    private func color(for cat: PartnerCategory) -> Color {
        switch cat {
        case .civic: return t.categorical[0]
        case .culturalEd: return t.categorical[1]
        case .industry: return t.categorical[2]
        case .individuals: return t.dim
        }
    }
}
