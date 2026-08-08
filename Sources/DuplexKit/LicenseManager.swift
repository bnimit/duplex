import Foundation
import Combine

/// License state machine. Persistence in UserDefaults, clock and client
/// injected for tests. Policy: activation and explicit server revocation
/// change state; network failure NEVER does (last-known-good wins).
@MainActor
public final class LicenseManager: ObservableObject {
    public enum State: Equatable {
        case free
        case licensed(keySuffix: String, activatedAt: Date)
    }

    @Published public private(set) var state: State = .free
    /// Set once when a revalidation discovers the key was revoked; the GUI
    /// shows it and clears it.
    @Published public var revocationNotice: String?

    public static let revalidationInterval: TimeInterval = 7 * 24 * 3600

    private enum Keys {
        static let key = "license.key"
        static let activationID = "license.activationID"
        static let activatedAt = "license.activatedAt"
        static let lastValidated = "license.lastValidated"
    }

    private let client: LicenseClient
    private let defaults: UserDefaults
    private let now: () -> Date

    public init(client: LicenseClient = DodoLicenseClient(),
                defaults: UserDefaults = .standard,
                now: @escaping () -> Date = Date.init) {
        self.client = client
        self.defaults = defaults
        self.now = now
        if let key = defaults.string(forKey: Keys.key) {
            let activatedAt = defaults.object(forKey: Keys.activatedAt) as? Date ?? now()
            state = .licensed(keySuffix: Self.suffix(of: key), activatedAt: activatedAt)
        }
    }

    public var isLicensed: Bool {
        if case .licensed = state { return true }
        return false
    }

    public func activate(key: String) async throws {
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
        let activation = try await client.activate(
            key: trimmed, instanceName: Host.current().localizedName ?? "Mac")
        let stamp = now()
        defaults.set(trimmed, forKey: Keys.key)
        defaults.set(activation.activationID, forKey: Keys.activationID)
        defaults.set(stamp, forKey: Keys.activatedAt)
        defaults.set(stamp, forKey: Keys.lastValidated)
        state = .licensed(keySuffix: Self.suffix(of: trimmed), activatedAt: stamp)
    }

    public func revalidateIfDue() async {
        guard case .licensed = state, let key = defaults.string(forKey: Keys.key) else { return }
        let last = defaults.object(forKey: Keys.lastValidated) as? Date ?? .distantPast
        // Due when the interval has passed, OR when the clock has gone
        // backwards (now < last): a rolled-back clock triggers the very
        // revalidation it would otherwise dodge.
        let elapsed = now().timeIntervalSince(last)
        guard elapsed >= Self.revalidationInterval || elapsed < 0 else { return }
        do {
            let valid = try await client.validate(
                key: key, activationID: defaults.string(forKey: Keys.activationID))
            if valid {
                defaults.set(now(), forKey: Keys.lastValidated)
            } else {
                clearPersisted()
                state = .free
                revocationNotice = "Your Duplex license is no longer valid (it may have been refunded or disabled). Existing instances keep working; creating more than one requires a license."
            }
        } catch {
            // Network failure: keep last-known-good, try again next time.
        }
    }

    public func deactivate() async throws {
        if let key = defaults.string(forKey: Keys.key),
           let activationID = defaults.string(forKey: Keys.activationID) {
            do {
                try await client.deactivate(key: key, activationID: activationID)
            } catch LicenseClientError.keyInvalid {
                // The server explicitly reports this activation no longer exists
                // (deactivated elsewhere). Local state must still clear.
            }
            // Transport failures (.network) propagate and skip the clear:
            // we could not confirm anything with the server, so keep state.
        }
        clearPersisted()
        state = .free
    }

    private func clearPersisted() {
        [Keys.key, Keys.activationID, Keys.activatedAt, Keys.lastValidated]
            .forEach { defaults.removeObject(forKey: $0) }
    }

    private static func suffix(of key: String) -> String { String(key.suffix(8)) }
}
