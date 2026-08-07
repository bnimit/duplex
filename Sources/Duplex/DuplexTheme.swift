import SwiftUI

/// Duplex's visual identity, derived from the app icon: an indigo field,
/// glass surfaces, and a coral state dot. Everything else rides native
/// materials and semantic colors so light and dark mode both hold up.
enum DuplexTheme {
    /// Brand indigo (#6E5BFF): the app-wide tint for actions and focus.
    static let indigo = Color(red: 0x6E / 255.0, green: 0x5B / 255.0, blue: 1.0)
    /// Badge coral (#F0503C): reserved for small state moments (free-tier dot).
    static let coral = Color(red: 0xF0 / 255.0, green: 0x50 / 255.0, blue: 0x3C / 255.0)

    static let cardCorner: CGFloat = 12
}

/// Card container: a native surface with soft elevation and a gentle hover
/// lift. The lift is disabled when Reduce Motion is on.
struct InstanceCardStyle: ViewModifier {
    let hovering: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content
            .background(
                RoundedRectangle(cornerRadius: DuplexTheme.cardCorner, style: .continuous)
                    .fill(Color(nsColor: .controlBackgroundColor))
                    .shadow(color: .black.opacity(hovering ? 0.16 : 0.07),
                            radius: hovering ? 10 : 5, y: hovering ? 4 : 2)
            )
            .overlay(
                RoundedRectangle(cornerRadius: DuplexTheme.cardCorner, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.06))
            )
            .scaleEffect(hovering && !reduceMotion ? 1.012 : 1)
            .animation(reduceMotion ? nil : .spring(response: 0.3, dampingFraction: 0.8),
                       value: hovering)
    }
}
