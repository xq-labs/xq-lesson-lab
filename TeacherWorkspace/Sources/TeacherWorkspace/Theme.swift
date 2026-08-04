import SwiftUI

extension Color {
    init(hex: UInt32, alpha: Double = 1) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: alpha
        )
    }
}

struct Theme {
    var bg: Color
    var side: Color
    var card: Color
    var head: Color
    var border: Color
    var text: Color
    var sub: Color
    var dim: Color
    var hover: Color
    var active: Color
    var input: Color
    var bubble: Color
    var accent: Color
    var accentSoft: Color
    var sendBg: Color
    var sendFg: Color
    var green: Color
    var red: Color
    var scrim: Color
    var isDark: Bool
    /// Category colors for competency/partner/tag taxonomies (rings, node
    /// graphs, chip kinds). Capped at 3 — validated as distinguishable in
    /// both modes; a 4th slot fails the all-pairs check, so a 4th category
    /// folds to a neutral color instead of a new hue.
    var categorical: [Color]

    static let dark = Theme(
        bg: Color(hex: 0x212121),
        side: Color(hex: 0x1A1A19),
        card: Color(hex: 0x2E2E2C),
        head: Color(hex: 0x343432),
        border: Color(hex: 0x3B3B38),
        text: Color(hex: 0xEDEDEB),
        sub: Color(hex: 0xA6A49C),
        dim: Color(hex: 0x807E76),
        hover: Color(hex: 0x333331),
        active: Color(hex: 0x3A3A37),
        input: Color(hex: 0x2F2F2E),
        bubble: Color(hex: 0x323230),
        accent: Color(hex: 0x7D9BEB),
        accentSoft: Color(hex: 0x7D9BEB, alpha: 0.14),
        sendBg: Color(hex: 0xECECEA),
        sendFg: Color(hex: 0x212121),
        green: Color(hex: 0x5BBA7D),
        red: Color(hex: 0xE0796C),
        scrim: Color(hex: 0x000000, alpha: 0.55),
        isDark: true,
        categorical: [Color(hex: 0x3987E5), Color(hex: 0xD95926), Color(hex: 0x199E70)]
    )

    static let light = Theme(
        bg: Color(hex: 0xFCFBF9),
        side: Color(hex: 0xF4F3EF),
        card: Color(hex: 0xFFFFFF),
        head: Color(hex: 0xF7F6F1),
        border: Color(hex: 0xE7E4DD),
        text: Color(hex: 0x22211D),
        sub: Color(hex: 0x75726A),
        dim: Color(hex: 0x94917F),
        hover: Color(hex: 0xECEAE2),
        active: Color(hex: 0xE9E7DD),
        input: Color(hex: 0xFFFFFF),
        bubble: Color(hex: 0xEFEDE6),
        accent: Color(hex: 0x3E68CE),
        accentSoft: Color(hex: 0xEBEFFA),
        sendBg: Color(hex: 0x3E68CE),
        sendFg: Color(hex: 0xFFFFFF),
        green: Color(hex: 0x4CA46A),
        red: Color(hex: 0xC0503E),
        scrim: Color(hex: 0x201E18, alpha: 0.35),
        isDark: false,
        categorical: [Color(hex: 0x2A78D6), Color(hex: 0xEB6834), Color(hex: 0x1BAF7A)]
    )
}

/// Rounded hover-highlight backing used by most buttons in the design.
struct HoverHighlight: ViewModifier {
    var radius: CGFloat
    var hoverColor: Color
    var baseColor: Color = .clear
    @State private var hovering = false

    func body(content: Content) -> some View {
        content
            .background(RoundedRectangle(cornerRadius: radius, style: .continuous)
                .fill(hovering ? hoverColor : baseColor))
            .onHover { hovering = $0 }
    }
}

extension View {
    func hoverHighlight(radius: CGFloat, hover: Color, base: Color = .clear) -> some View {
        modifier(HoverHighlight(radius: radius, hoverColor: hover, baseColor: base))
    }
}
