import AppKit

public enum URLSchemeRouter {
    /// Schemes the whole Mac depends on. Some apps register for these (Codex claims http and
    /// https), and "Route Links Here" must never make an instance the default browser.
    static let systemSchemes: Set<String> = ["http", "https", "file", "mailto"]

    public static func routable(_ schemes: [String]) -> [String] {
        schemes.filter { !systemSchemes.contains($0.lowercased()) }
    }

    public static func currentHandler(forScheme scheme: String) -> URL? {
        guard let probe = URL(string: "\(scheme)://duplex-probe") else { return nil }
        return NSWorkspace.shared.urlForApplication(toOpen: probe)
    }

    public static func setHandler(appURL: URL, forScheme scheme: String,
                                  completion: @escaping (Error?) -> Void) {
        NSWorkspace.shared.setDefaultApplication(
            at: appURL, toOpenURLsWithScheme: scheme, completion: completion)
    }
}
