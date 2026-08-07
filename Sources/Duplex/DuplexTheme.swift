import SwiftUI

/// Duplex's visual identity: a saturated indigo-to-coral backdrop showing
/// through frosted material panels, white floating cards, and one vivid
/// indigo accent. Derived from the app icon's palette; both color schemes
/// get their own tuning.
enum DuplexTheme {
    /// Brand indigo (#6E5BFF): the single saturated accent.
    static let indigo = Color(red: 0x6E / 255.0, green: 0x5B / 255.0, blue: 1.0)
    /// Badge coral (#F0503C): reserved for small state moments.
    static let coral = Color(red: 0xF0 / 255.0, green: 0x50 / 255.0, blue: 0x3C / 255.0)

    static let cardCorner: CGFloat = 14

    /// The vivid backdrop the frosted layers sit on.
    static func windowGradient(_ scheme: ColorScheme) -> LinearGradient {
        let colors: [Color] = scheme == .dark
            ? [Color(red: 0.16, green: 0.13, blue: 0.34),
               Color(red: 0.10, green: 0.09, blue: 0.18),
               Color(red: 0.22, green: 0.10, blue: 0.16)]
            : [Color(red: 0.55, green: 0.47, blue: 1.0),
               Color(red: 0.72, green: 0.62, blue: 0.98),
               Color(red: 0.98, green: 0.62, blue: 0.55)]
        return LinearGradient(colors: colors, startPoint: .topLeading, endPoint: .bottomTrailing)
    }

    /// Stable pastel tint for an app's tag pill (deterministic across launches).
    static func tagTint(for key: String) -> Color {
        let palette: [Color] = [
            Color(red: 0.30, green: 0.69, blue: 0.49),  // green
            Color(red: 0.36, green: 0.56, blue: 0.94),  // blue
            Color(red: 0.94, green: 0.58, blue: 0.28),  // orange
            Color(red: 0.63, green: 0.47, blue: 0.92),  // purple
            Color(red: 0.90, green: 0.44, blue: 0.62),  // pink
            Color(red: 0.26, green: 0.68, blue: 0.71),  // teal
        ]
        let sum = key.unicodeScalars.reduce(0) { $0 &+ Int($1.value) }
        return palette[sum % palette.count]
    }
}

/// Trello-style tag pill: tinted capsule with a darker tinted label.
struct TagPill: View {
    let text: String
    let tint: Color

    var body: some View {
        Text(text)
            .font(.system(size: 10.5, weight: .semibold))
            .foregroundStyle(tint)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(Capsule().fill(tint.opacity(0.16)))
            .lineLimit(1)
    }
}

/// Small metadata chip: icon + value, quiet gray.
struct MetaChip: View {
    let systemImage: String
    let text: String

    var body: some View {
        HStack(spacing: 3) {
            Image(systemName: systemImage).font(.system(size: 9.5))
            Text(text).font(.system(size: 10.5, weight: .medium, design: .monospaced))
        }
        .foregroundStyle(.secondary)
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
                    .shadow(color: .black.opacity(hovering ? 0.20 : 0.10),
                            radius: hovering ? 12 : 6, y: hovering ? 5 : 2)
            )
            .scaleEffect(hovering && !reduceMotion ? 1.012 : 1)
            .animation(reduceMotion ? nil : .spring(response: 0.3, dampingFraction: 0.8),
                       value: hovering)
    }
}
