import Foundation
import Combine

/// Tells the user when a newer Duplex has been published. It never downloads or
/// installs anything: the user updates through Homebrew or the release page.
/// Persistence in UserDefaults, clock and feed injected for tests.
@MainActor
public final class UpdateManager: ObservableObject {
    /// Set only when a release newer than this build exists and the user has
    /// not dismissed that particular version.
    @Published public private(set) var available: AvailableUpdate?

    public static let checkInterval: TimeInterval = 24 * 3600

    private enum Keys {
        static let lastChecked = "update.lastChecked"
        static let dismissedVersion = "update.dismissedVersion"
        static let automatic = "update.automaticChecks"
    }

    private let feed: ReleaseFeed
    private let currentVersion: String
    private let defaults: UserDefaults
    private let now: () -> Date

    public init(feed: ReleaseFeed, currentVersion: String,
                defaults: UserDefaults = .standard,
                now: @escaping () -> Date = Date.init) {
        self.feed = feed
        self.currentVersion = currentVersion
        self.defaults = defaults
        self.now = now
        // Absent means on: checking is the default, opting out is deliberate.
        if defaults.object(forKey: Keys.automatic) == nil {
            defaults.set(true, forKey: Keys.automatic)
        }
    }

    public var automaticChecksEnabled: Bool {
        get { defaults.bool(forKey: Keys.automatic) }
        set {
            objectWillChange.send()
            defaults.set(newValue, forKey: Keys.automatic)
            if !newValue { available = nil }
        }
    }

    /// Runs at most once a day, and only while automatic checks are on.
    public func checkIfDue() async {
        guard automaticChecksEnabled else { return }
        let last = defaults.object(forKey: Keys.lastChecked) as? Date ?? .distantPast
        // Due when the interval has passed, OR when the clock has gone backwards
        // (now < last), so a rolled-back clock cannot dodge the check forever.
        let elapsed = now().timeIntervalSince(last)
        guard elapsed >= Self.checkInterval || elapsed < 0 else { return }
        await check()
    }

    /// An explicit check by the user: the click is the consent, so it ignores
    /// both the interval and the automatic-checks preference.
    public func checkNow() async {
        await check()
    }

    private func check() async {
        defaults.set(now(), forKey: Keys.lastChecked)
        guard let release = try? await feed.latestRelease() else {
            // Offline, rate limited, or an unreadable reply: stay quiet and
            // try again after the interval.
            return
        }
        guard SemanticVersion.isNewer(release.version, than: currentVersion) else {
            available = nil
            return
        }
        guard release.version != defaults.string(forKey: Keys.dismissedVersion) else { return }
        available = release
    }

    /// Hides this version for good. A later version surfaces normally.
    public func dismiss() {
        if let version = available?.version {
            defaults.set(version, forKey: Keys.dismissedVersion)
        }
        available = nil
    }
}
