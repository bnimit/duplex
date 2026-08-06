import Foundation

public enum SlugGenerator {
    public static func slug(from name: String, existing: Set<String>) -> String {
        let folded = name.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .init(identifier: "en_US"))
        let mapped = folded.lowercased().map { ch -> Character in
            (ch.isLetter || ch.isNumber) && ch.isASCII ? ch : "-"
        }
        var base = String(mapped)
        while base.contains("--") { base = base.replacingOccurrences(of: "--", with: "-") }
        base = base.trimmingCharacters(in: CharacterSet(charactersIn: "-"))
        if base.isEmpty { base = "instance" }
        // "app" is reserved: it would collide with Duplex.app's own bundle-ID
        // namespace (historically com.duplex.app), so always treat it as taken.
        if base == "app" { base = "app-instance" }

        if !existing.contains(base) { return base }
        var n = 2
        while existing.contains("\(base)-\(n)") { n += 1 }
        return "\(base)-\(n)"
    }
}
