import SwiftUI

/// Duplex's visual identity: soft pastel gradient atmosphere, white floating
/// cards, and one vivid indigo accent, derived from the app icon's palette.
/// Dark mode swaps the pastels for deep indigo washes; semantic colors keep
/// text and surfaces legible in both.
enum DuplexTheme {
    /// Brand indigo (#6E5BFF): the single saturated accent.
    static let indigo = Color(red: 0x6E / 255.0, green: 0x5B / 255.0, blue: 1.0)
    /// Badge coral (#F0503C): reserved for small state moments (free-tier dot).
    static let coral = Color(red: 0xF0 / 255.0, green: 0x50 / 255.0, blue: 0x3C / 255.0)

    static let cardCorner: CGFloat = 16

    /// The window's atmosphere: lavender fading to warm white (light) or a
    /// deep indigo-tinted night wash (dark).
    static func windowGradient(_ scheme: ColorScheme) -> LinearGradient {
        let colors: [Color] = scheme == .dark
            ? [Color(red: 0.11, green: 0.10, blue: 0.19), Color(red: 0.07, green: 0.07, blue: 0.09)]
            : [Color(red: 0.93, green: 0.91, blue: 1.0), Color(red: 0.99, green: 0.98, blue: 0.97)]
        return LinearGradient(colors: colors, startPoint: .topLeading, endPoint: .bottomTrailing)
    }

    /// The pastel wash inside a card's hero zone, behind the icon pair.
    static func heroGradient(_ scheme: ColorScheme) -> LinearGradient {
        LinearGradient(
            colors: [indigo.opacity(scheme == .dark ? 0.28 : 0.14),
                     indigo.opacity(0.02)],
            startPoint: .top, endPoint: .bottom)
    }
}

/// The one saturated element on any screen: a filled indigo pill.
struct PillButtonStyle: ButtonStyle {
    var compact = false
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: compact ? 12 : 13, weight: .semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, compact ? 14 : 18)
            .padding(.vertical, compact ? 5 : 8)
            .background(Capsule().fill(DuplexTheme.indigo.opacity(
                isEnabled ? (configuration.isPressed ? 0.75 : 1) : 0.4)))
            .contentShape(Capsule())
    }
}

/// A dimensional keyboard keycap, for shortcut hints ("or press ⌘ N").
struct Keycap: View {
    let label: String

    var body: some View {
        Text(label)
            .font(.system(size: 12, weight: .medium, design: .rounded))
            .foregroundStyle(.secondary)
            .frame(width: 26, height: 24)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(Color(nsColor: .controlBackgroundColor))
                    .shadow(color: .black.opacity(0.12), radius: 2, y: 1.5))
    }
}

/// Card container: a white floating surface with soft elevation and a gentle
/// hover lift. The lift is disabled when Reduce Motion is on.
struct InstanceCardStyle: ViewModifier {
    let hovering: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content
            .background(
                RoundedRectangle(cornerRadius: DuplexTheme.cardCorner, style: .continuous)
                    .fill(Color(nsColor: .controlBackgroundColor))
                    .shadow(color: .black.opacity(hovering ? 0.18 : 0.09),
                            radius: hovering ? 14 : 8, y: hovering ? 6 : 3)
            )
            .overlay(
                RoundedRectangle(cornerRadius: DuplexTheme.cardCorner, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.05))
            )
            .scaleEffect(hovering && !reduceMotion ? 1.012 : 1)
            .animation(reduceMotion ? nil : .spring(response: 0.3, dampingFraction: 0.8),
                       value: hovering)
    }
}
