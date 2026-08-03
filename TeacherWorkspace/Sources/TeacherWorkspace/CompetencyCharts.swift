import SwiftUI
import Foundation

/// Reusable chart primitives for the competency-engine screens (Learner
/// Profiles / Community Graph / Project Matcher). Pure data-in views — no
/// `AppState` dependency — so they compose the same way `LibraryCard` does.
/// Every screen's static demo data is small and fixed, so these use direct
/// geometry (points on a circle, a straight polyline) rather than a real
/// layout or animation engine.

// MARK: - Donut ring chart (competency growth)

struct DonutRingChart: View {
    var scores: [CompetencyScore]
    var theme: Theme
    var diameter: CGFloat = 112
    var lineWidth: CGFloat = 10

    var body: some View {
        HStack(spacing: 18) {
            ZStack {
                ForEach(Array(scores.enumerated()), id: \.offset) { idx, score in
                    ring(score: score, color: color(for: idx), fraction: 1 - CGFloat(idx) * 0.26)
                }
            }
            .frame(width: diameter, height: diameter)

            VStack(alignment: .leading, spacing: 9) {
                ForEach(Array(scores.enumerated()), id: \.offset) { idx, score in
                    HStack(spacing: 7) {
                        Circle().fill(color(for: idx)).frame(width: 8, height: 8)
                        Text(score.name)
                            .font(.system(size: 12.5))
                            .foregroundStyle(theme.text)
                        Spacer(minLength: 10)
                        Text("\(score.score)")
                            .font(.system(size: 12).monospacedDigit())
                            .foregroundStyle(theme.dim)
                    }
                }
            }
        }
    }

    private func color(for idx: Int) -> Color {
        theme.categorical[idx % theme.categorical.count]
    }

    private func ring(score: CompetencyScore, color: Color, fraction: CGFloat) -> some View {
        ZStack {
            Circle()
                .stroke(theme.border, style: StrokeStyle(lineWidth: lineWidth))
                .scaleEffect(fraction)
            Circle()
                .trim(from: 0, to: CGFloat(score.score) / 100)
                .stroke(color, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .scaleEffect(fraction)
        }
    }
}

// MARK: - Sparkline (confidence trend)

struct Sparkline: View {
    var points: [ConfidencePoint]
    var color: Color
    var theme: Theme

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height
            let stepX = points.count > 1 ? w / CGFloat(points.count - 1) : 0

            let positions = points.enumerated().map { i, pt in
                CGPoint(x: CGFloat(i) * stepX, y: h - (CGFloat(pt.value) / 100) * h)
            }

            let line = Path { p in
                for (i, point) in positions.enumerated() {
                    if i == 0 { p.move(to: point) } else { p.addLine(to: point) }
                }
            }

            ZStack {
                line.stroke(color, style: StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round))
                ForEach(Array(points.enumerated()), id: \.offset) { i, pt in
                    if pt.note != nil {
                        Circle()
                            .fill(theme.card)
                            .overlay(Circle().stroke(color, lineWidth: 2.5))
                            .frame(width: 9, height: 9)
                            .position(positions[i])
                    }
                }
                if let lastPosition = positions.last {
                    Circle()
                        .fill(color)
                        .frame(width: 8, height: 8)
                        .position(lastPosition)
                }
            }
        }
    }
}

// MARK: - Weekly bar chart (engagement)

struct WeeklyBarChart: View {
    var weeks: [EngagementWeek]
    var color: Color

    var body: some View {
        GeometryReader { geo in
            let spacing: CGFloat = 4
            let count = max(weeks.count, 1)
            let barWidth = (geo.size.width - spacing * CGFloat(count - 1)) / CGFloat(count)
            HStack(alignment: .bottom, spacing: spacing) {
                ForEach(weeks) { wk in
                    RoundedRectangle(cornerRadius: 3, style: .continuous)
                        .fill(color.opacity(0.35 + 0.65 * Double(wk.value) / 100))
                        .frame(width: max(barWidth, 1),
                               height: max(4, geo.size.height * CGFloat(wk.value) / 100))
                }
            }
            .frame(width: geo.size.width, height: geo.size.height, alignment: .bottom)
        }
    }
}

// MARK: - Node-link graph (collaboration network / community partners)

struct GraphNode: Identifiable {
    var id: String { label }
    var label: String
    var color: Color
    var strength: Double // 0...1 — drives edge thickness and tint
    var radius: CGFloat = 22
}

struct NodeLinkGraph: View {
    var centerLabel: String
    var centerSublabel: String?
    var nodes: [GraphNode]
    var theme: Theme

    var body: some View {
        GeometryReader { geo in
            let center = CGPoint(x: geo.size.width / 2, y: geo.size.height / 2)
            let radius = min(geo.size.width, geo.size.height) / 2 - 44
            let n = max(nodes.count, 1)
            let positions = (0..<nodes.count).map { position(for: $0, of: n, center: center, radius: radius) }

            ZStack {
                ForEach(Array(nodes.enumerated()), id: \.element.id) { idx, node in
                    let pos = positions[idx]
                    Path { p in
                        p.move(to: center)
                        p.addLine(to: pos)
                    }
                    .stroke(node.color.opacity(node.strength > 0.4 ? 0.9 : 0.5),
                            lineWidth: 1 + CGFloat(node.strength) * 4)
                }

                ForEach(Array(nodes.enumerated()), id: \.element.id) { idx, node in
                    let pos = positions[idx]
                    VStack(spacing: 3) {
                        Circle()
                            .fill(node.color.opacity(0.16))
                            .overlay(Circle().stroke(node.color, lineWidth: 1.5))
                            .frame(width: node.radius * 2, height: node.radius * 2)
                        Text(node.label)
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(theme.sub)
                            .multilineTextAlignment(.center)
                            .lineLimit(2)
                            .frame(width: 84)
                    }
                    .position(x: pos.x, y: pos.y - 4)
                }

                VStack(spacing: 1) {
                    Text(centerLabel)
                        .font(.system(size: 11.5, weight: .semibold))
                        .foregroundStyle(theme.bg)
                        .multilineTextAlignment(.center)
                        .lineLimit(2)
                    if let sub = centerSublabel {
                        Text(sub)
                            .font(.system(size: 9.5))
                            .foregroundStyle(theme.bg.opacity(0.7))
                    }
                }
                .frame(width: 78)
                .frame(width: 82, height: 82)
                .background(Circle().fill(theme.text))
                .position(center)
            }
        }
    }

    private func position(for idx: Int, of count: Int, center: CGPoint, radius: CGFloat) -> CGPoint {
        let angle = -Double.pi / 2 + 2 * Double.pi * Double(idx) / Double(count)
        return CGPoint(x: center.x + radius * CGFloat(cos(angle)),
                        y: center.y + radius * CGFloat(sin(angle)))
    }
}
