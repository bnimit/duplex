import Foundation

public struct LauncherConfig: Equatable {
    public let targetBundleID: String
    public let targetPath: String
    /// CFBundleExecutable of the target app (nil for 1.1 wrappers).
    public let targetExecutable: String?
    public let slug: String
    public let name: String
    /// Target version the clone was made from (nil for 1.1 wrappers).
    public let sourceVersion: String?

    public init(targetBundleID: String, targetPath: String, targetExecutable: String? = nil,
                slug: String, name: String? = nil, sourceVersion: String? = nil) {
        self.targetBundleID = targetBundleID
        self.targetPath = targetPath
        self.targetExecutable = targetExecutable
        self.slug = slug
        self.name = name ?? slug
        self.sourceVersion = sourceVersion
    }
}

public enum LauncherLogic {
    public static func config(from info: [String: Any]) -> LauncherConfig? {
        guard let bundleID = info[DuplexPlistKey.targetBundleID] as? String,
              let path = info[DuplexPlistKey.targetPath] as? String,
              let slug = info[DuplexPlistKey.instanceSlug] as? String
        else { return nil }
        return LauncherConfig(
            targetBundleID: bundleID, targetPath: path,
            targetExecutable: info[DuplexPlistKey.targetExecutable] as? String,
            slug: slug,
            name: info[DuplexPlistKey.instanceName] as? String,
            sourceVersion: info[DuplexPlistKey.sourceVersion] as? String)
    }

    public static func dataDir(slug: String, homePath: String) -> URL {
        URL(fileURLWithPath: homePath)
            .appendingPathComponent("Library/Application Support/Duplex")
            .appendingPathComponent(slug)
            .appendingPathComponent("data")
    }

    /// --use-mock-keychain: a clone has its own signing identity, so macOS denies it the
    /// original app's "Safe Storage" keychain item (which crashes Chromium's network service).
    /// The mock keychain encrypts the profile with a fixed key instead, the same model
    /// Chromium uses on Linux without a keyring.
    public static func execArguments(targetExecutable: String, dataDir: URL) -> [String] {
        [targetExecutable, "--user-data-dir=\(dataDir.path)", "--use-mock-keychain"]
    }

    /// Picks the target app bundle: LaunchServices resolution wins when it exists on disk,
    /// otherwise the recorded path (if it exists). Pure for testability.
    public static func resolveTarget(lsResolved: URL?, fallbackPath: String,
                                     fileExists: (String) -> Bool) -> URL? {
        if let resolved = lsResolved, fileExists(resolved.path) { return resolved }
        if fileExists(fallbackPath) { return URL(fileURLWithPath: fallbackPath) }
        return nil
    }

    /// True only when both versions are known and differ. Unknown on either side means
    /// "leave the clone alone".
    public static func needsResync(recorded: String?, installed: String?) -> Bool {
        guard let recorded, let installed else { return false }
        return recorded != installed
    }
}
