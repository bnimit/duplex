import AppKit

public enum URLSchemeRouter {
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
