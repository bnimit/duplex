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
        guard let bundleID = info[DuplyPlistKey.targetBundleID] as? String,
              let path = info[DuplyPlistKey.targetPath] as? String,
              let slug = info[DuplyPlistKey.instanceSlug] as? String
        else { return nil }
        return LauncherConfig(targetBundleID: bundleID, targetPath: path, slug: slug)
    }

    public static func dataDir(slug: String, homePath: String) -> URL {
        URL(fileURLWithPath: homePath)
            .appendingPathComponent("Library/Application Support/Duply")
            .appendingPathComponent(slug)
            .appendingPathComponent("data")
    }

    public static func execArguments(targetExecutable: String, dataDir: URL) -> [String] {
        [targetExecutable, "--user-data-dir=\(dataDir.path)"]
    }
}
