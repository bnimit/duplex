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

    /// Environment an instance needs beyond --user-data-dir, for apps that keep their login
    /// outside the Chromium profile. Codex's bundled app-server keeps settings and sign-in under
    /// CODEX_HOME (default ~/.codex) and names its keychain entry after that path, so without
    /// a private CODEX_HOME every Codex instance shares, and signs out, the original's account.
    /// Codex is recognized by its bundle ID or by the codex-cli it ships, so a renamed ID
    /// cannot quietly bring the shared login back. Pure for testability.
    public static func extraEnvironment(targetBundleID: String, targetURL: URL, dataDir: URL,
                                        fileExists: (String) -> Bool) -> [String: String] {
        let shipsCodexCLI = fileExists(targetURL.appendingPathComponent("Contents/Resources/codex-cli").path)
        guard targetBundleID == "com.openai.codex" || shipsCodexCLI else { return [:] }
        return ["CODEX_HOME": dataDir.deletingLastPathComponent().appendingPathComponent("codex-home").path]
    }

    /// Picks the target app bundle: LaunchServices resolution wins when it exists on disk,
    /// otherwise the recorded path (if it exists). Pure for testability.
    public static func resolveTarget(lsResolved: URL?, fallbackPath: String,
                                     fileExists: (String) -> Bool) -> URL? {
        if let resolved = lsResolved, fileExists(resolved.path) { return resolved }
        if fileExists(fallbackPath) { return URL(fileURLWithPath: fallbackPath) }
        return nil
    }

    /// How the installed original compares with the version a clone was built from.
    public enum VersionChange: Equatable {
        /// Identical, or unknown on either side: leave the clone alone.
        case unchanged
        /// The installed app is newer: rebuild the clone, so the vendor's own profile
        /// migration runs against a matching binary.
        case upgrade
        /// The installed app is OLDER than the clone. Rebuilding would hand a profile the
        /// clone's newer binary may already have migrated forward to an older binary, which
        /// Chromium can refuse to open, so this is never resynced silently.
        case downgrade
        /// The two differ but cannot be ordered: a version string that will not parse, or
        /// one that is numerically equal with different text ("1.2" against "1.2.0").
        /// Rebuilt, which is what Duplex did for every difference before ordering existed.
        case indeterminate

        /// True when the clone should be rebuilt from the installed app.
        public var rebuilds: Bool { self == .upgrade || self == .indeterminate }
    }

    /// What the launcher does before running an instance.
    public enum LaunchAction: Equatable {
        /// Run the clone as it is.
        case run
        /// Rebuild the clone from the installed original, then run it.
        case rebuild
        /// The original was rolled back and the clone still works: ask whether to open the
        /// newer clone anyway. Skipped once the user has already said yes to this exact change.
        case promptDowngrade
        /// The original was rolled back and the clone has lost its binary, so the only way
        /// forward is a rebuild from the older app: ask before doing it.
        case promptRebuildFromOlder
    }

    /// Pure decision for the launcher. `acknowledged` is whether the user already chose to
    /// open past this same downgrade (see `acknowledgementKey`).
    public static func action(change: VersionChange, binaryMissing: Bool,
                              acknowledged: Bool) -> LaunchAction {
        if change == .downgrade {
            if binaryMissing { return .promptRebuildFromOlder }
            return acknowledged ? .run : .promptDowngrade
        }
        return change.rebuilds || binaryMissing ? .rebuild : .run
    }

    /// Identifies one specific rollback, so an "Open Anyway" answer is remembered for it and
    /// a later, different version change asks again.
    public static func acknowledgementKey(recorded: String?, installed: String?) -> String {
        "\(recorded ?? "?") -> \(installed ?? "?")"
    }

    /// Orders two `InstancePlist.sourceVersion` strings ("<short> (<build>)"). Unknown on
    /// either side means "leave the clone alone"; anything that will not parse falls back to
    /// `.indeterminate` so a difference is never silently ignored.
    public static func versionChange(recorded: String?, installed: String?) -> VersionChange {
        guard let recorded, let installed else { return .unchanged }
        if recorded == installed { return .unchanged }
        guard let from = AppVersion(recorded), let to = AppVersion(installed) else {
            // A suffixed short version ("2.0.0-beta.3", "1.4.2b") will not parse, but
            // CFBundleVersion is usually a plain number, so order by that when both have one.
            guard let fromBuild = AppVersion.buildComponents(of: recorded),
                  let toBuild = AppVersion.buildComponents(of: installed),
                  !fromBuild.isEmpty, !toBuild.isEmpty
            else { return .indeterminate }
            if AppVersion.less(fromBuild, toBuild) { return .upgrade }
            if AppVersion.less(toBuild, fromBuild) { return .downgrade }
            return .indeterminate
        }
        if from < to { return .upgrade }
        if to < from { return .downgrade }
        return .indeterminate
    }
}

/// A target app's version, ordered numerically rather than as text: `CFBundleShortVersionString`
/// first, `CFBundleVersion` only as a tiebreaker. The two are kept apart on purpose — comparing
/// every number in "1.0 (100)" as one list would read "1.0.1 (101)" as a downgrade.
struct AppVersion: Comparable {
    let short: [Int]
    let build: [Int]

    /// Parses "<short> (<build>)", "<short>" or "(<build>)" as written by
    /// `InstancePlist.sourceVersion(of:)`. nil when any component is not a plain number.
    init?(_ text: String) {
        let (shortText, buildText) = Self.split(text)
        guard let short = Self.components(shortText), let build = Self.components(buildText),
              !(short.isEmpty && build.isEmpty)
        else { return nil }
        self.short = short
        self.build = build
    }

    /// Splits "<short> (<build>)" into its two texts; either may be empty.
    private static func split(_ text: String) -> (short: String, build: String) {
        var shortText = text.trimmingCharacters(in: .whitespaces)
        var buildText = ""
        if shortText.hasSuffix(")"), let open = shortText.lastIndex(of: "(") {
            buildText = String(shortText[shortText.index(after: open)..<shortText.index(before: shortText.endIndex)])
            shortText = String(shortText[shortText.startIndex..<open]).trimmingCharacters(in: .whitespaces)
        }
        return (shortText, buildText)
    }

    /// The numeric build components of a version string, or nil when the build is not plain
    /// numbers. Independent of whether the short version parses.
    static func buildComponents(of text: String) -> [Int]? {
        components(split(text).build)
    }

    private static func components(_ text: String) -> [Int]? {
        if text.isEmpty { return [] }
        var result: [Int] = []
        for part in text.split(separator: ".", omittingEmptySubsequences: false) {
            guard !part.isEmpty, part.allSatisfy(\.isASCII), part.allSatisfy(\.isNumber),
                  let value = Int(part)
            else { return nil }
            result.append(value)
        }
        return result
    }

    /// Equal when both parts are numerically equal, so "1.2" == "1.2.0" and `<` agrees.
    static func == (lhs: AppVersion, rhs: AppVersion) -> Bool {
        !less(lhs.short, rhs.short) && !less(rhs.short, lhs.short)
            && !less(lhs.build, rhs.build) && !less(rhs.build, lhs.build)
    }

    static func < (lhs: AppVersion, rhs: AppVersion) -> Bool {
        if less(lhs.short, rhs.short) { return true }
        if less(rhs.short, lhs.short) { return false }
        return less(lhs.build, rhs.build)
    }

    /// Component-by-component, treating a missing component as 0 so "1.2" equals "1.2.0".
    static func less(_ lhs: [Int], _ rhs: [Int]) -> Bool {
        for index in 0..<max(lhs.count, rhs.count) {
            let left = index < lhs.count ? lhs[index] : 0
            let right = index < rhs.count ? rhs[index] : 0
            if left != right { return left < right }
        }
        return false
    }
}
