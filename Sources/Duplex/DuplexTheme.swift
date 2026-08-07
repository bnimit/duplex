import SwiftUI

/// Duplex's identity in the native macOS design language: flat content,
/// system materials and chrome (Liquid Glass on macOS 26), and one brand
/// accent used as the app-wide tint.
enum DuplexTheme {
    /// Brand indigo (#6E5BFF): the app-wide tint.
    static let indigo = Color(red: 0x6E / 255.0, green: 0x5B / 255.0, blue: 1.0)
    /// Badge coral (#F0503C): reserved for small state moments (free-tier dot).
    static let coral = Color(red: 0xF0 / 255.0, green: 0x50 / 255.0, blue: 0x3C / 255.0)
}

/// Prominent action button: Liquid Glass on macOS 26, bordered-prominent
/// (tinted) on earlier systems.
struct ProminentActionStyle: ViewModifier {
    func body(content: Content) -> some View {
        if #available(macOS 26.0, *) {
            content.buttonStyle(.glassProminent)
        } else {
            content.buttonStyle(.borderedProminent)
        }
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
