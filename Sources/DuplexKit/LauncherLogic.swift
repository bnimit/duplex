import Foundation

public struct LauncherConfig: Equatable {
    public let targetBundleID: String
    public let targetPath: String
    public let slug: String

    public init(targetBundleID: String, targetPath: String, slug: String) {
        self.targetBundleID = targetBundleID
        self.targetPath = targetPath
        self.slug = slug
    }
}

public enum LauncherLogic {
    public static func config(from info: [String: Any]) -> LauncherConfig? {
        guard let bundleID = info[DuplexPlistKey.targetBundleID] as? String,
              let path = info[DuplexPlistKey.targetPath] as? String,
              let slug = info[DuplexPlistKey.instanceSlug] as? String
        else { return nil }
        return LauncherConfig(targetBundleID: bundleID, targetPath: path, slug: slug)
    }

    public static func dataDir(slug: String, homePath: String) -> URL {
        URL(fileURLWithPath: homePath)
            .appendingPathComponent("Library/Application Support/Duplex")
            .appendingPathComponent(slug)
            .appendingPathComponent("data")
    }

    public static func execArguments(targetExecutable: String, dataDir: URL) -> [String] {
        [targetExecutable, "--user-data-dir=\(dataDir.path)"]
    }

    /// Picks the target app bundle: LaunchServices resolution wins when it exists on disk,
    /// otherwise the recorded path (if it exists). Pure for testability.
    public static func resolveTarget(lsResolved: URL?, fallbackPath: String,
                                     fileExists: (String) -> Bool) -> URL? {
        if let resolved = lsResolved, fileExists(resolved.path) { return resolved }
        if fileExists(fallbackPath) { return URL(fileURLWithPath: fallbackPath) }
        return nil
    }
}
