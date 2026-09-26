import SwiftUI

/// FOLDSPACE cockpit palette: dark navy hull, cyan HUD lines, orange warnings, monospaced readouts.
enum Theme {
    static let bg = Color(hex: "05070F")
    static let panel = Color(hex: "0B1020")
    static let accent = Color(hex: "3DF2FF")
    static let warn = Color(hex: "FFB238")
    static let danger = Color(hex: "FF3B5C")
    static let gain = Color(hex: "4DFF9A")
    static let dim = Color(hex: "6B7A99")

    /// Readout colour for a hull percentage 0...100.
    static func hullColor(_ hull: Double) -> Color {
        hull < 40 ? danger : (hull < 70 ? warn : gain)
    }
}

extension Color {
    /// Accepts "RRGGBB", "#RRGGBB" or "RRGGBBAA". Falls back to black for garbage input.
    init(hex: String) {
        var s = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.hasPrefix("#") { s.removeFirst() }
        var value: UInt64 = 0
        Scanner(string: s).scanHexInt64(&value)
        let r: Double, g: Double, b: Double, a: Double
        if s.count == 8 {
            r = Double((value >> 24) & 0xFF) / 255
            g = Double((value >> 16) & 0xFF) / 255
            b = Double((value >> 8) & 0xFF) / 255
            a = Double(value & 0xFF) / 255
        } else {
            r = Double((value >> 16) & 0xFF) / 255
            g = Double((value >> 8) & 0xFF) / 255
            b = Double(value & 0xFF) / 255
            a = 1
        }
        self.init(.sRGB, red: r, green: g, blue: b, opacity: a)
    }
}

extension Font {
    /// Monospaced system font — every cockpit readout uses this.
    static func mono(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight, design: .monospaced)
    }
}

// MARK: - Shared cockpit chrome

/// Thin 1 px bordered panel used across the console, HUD and the hinge simulator.
struct CockpitPanelModifier: ViewModifier {
    var tint: Color
    var padding: CGFloat
    var cornerRadius: CGFloat

    func body(content: Content) -> some View {
        content
            .padding(padding)
            .background(
                Theme.panel.opacity(0.85),
                in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            )
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(tint.opacity(0.35), lineWidth: 1)
            )
    }
}

extension View {
    func cockpitPanel(tint: Color = Theme.accent, padding: CGFloat = 10, cornerRadius: CGFloat = 8) -> some View {
        modifier(CockpitPanelModifier(tint: tint, padding: padding, cornerRadius: cornerRadius))
    }

    /// Soft neon glow for HUD text and lines.
    func hudGlow(_ color: Color = Theme.accent, radius: CGFloat = 6) -> some View {
        shadow(color: color.opacity(0.75), radius: radius)
    }
}

/// Monospaced, 1 px bordered cockpit button. `filled` inverts it for primary actions.
struct CockpitButtonStyle: ButtonStyle {
    var tint: Color = Theme.accent
    var filled: Bool = false
    var size: CGFloat = 11
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.mono(size, weight: .semibold))
            .tracking(0.8)
            .foregroundStyle(filled ? Theme.bg : tint)
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .frame(minHeight: 30)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(filled ? tint : tint.opacity(configuration.isPressed ? 0.25 : 0.08))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .strokeBorder(tint.opacity(0.6), lineWidth: 1)
            )
            .opacity(isEnabled ? 1 : 0.35)
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

extension ButtonStyle where Self == CockpitButtonStyle {
    static func cockpit(_ tint: Color = Theme.accent, filled: Bool = false, size: CGFloat = 11) -> CockpitButtonStyle {
        CockpitButtonStyle(tint: tint, filled: filled, size: size)
    }
}

/// Horizontal 0...1 meter with a thin border — hull, charge and core readouts.
struct CockpitMeter: View {
    var value: Double
    var tint: Color = Theme.accent
    var height: CGFloat = 6

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.white.opacity(0.06))
                Capsule()
                    .fill(tint)
                    .frame(width: max(0, min(1, value)) * geo.size.width)
                    .shadow(color: tint.opacity(0.7), radius: 4)
            }
            .overlay(Capsule().strokeBorder(tint.opacity(0.35), lineWidth: 1))
        }
        .frame(height: height)
        .animation(.linear(duration: 0.1), value: value)
    }
}

/// Tiny uppercase tracked caption used for HUD labels.
struct CockpitCaption: View {
    var text: String
    var color: Color

    init(_ text: String, color: Color = Theme.dim) {
        self.text = text
        self.color = color
    }

    var body: some View {
        Text(text.uppercased())
            .font(.mono(8, weight: .semibold))
            .tracking(1.2)
            .foregroundStyle(color)
    }
}
