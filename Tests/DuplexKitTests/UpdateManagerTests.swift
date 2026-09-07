import XCTest
@testable import DuplexKit

/// Feed double: records calls and returns a scripted result.
private final class StubFeed: ReleaseFeed, @unchecked Sendable {
    var result: Result<AvailableUpdate, Error>
    private(set) var calls = 0
    init(_ result: Result<AvailableUpdate, Error>) { self.result = result }
    func latestRelease() async throws -> AvailableUpdate {
        calls += 1
        return try result.get()
    }
}

@MainActor
final class UpdateManagerTests: XCTestCase {
    private var defaults: UserDefaults!
    private var suiteName: String!

    override func setUpWithError() throws {
        suiteName = "duplex-update-tests-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
    }

    override func tearDownWithError() throws {
        defaults.removePersistentDomain(forName: suiteName)
    }

    private func update(_ version: String) -> AvailableUpdate {
        AvailableUpdate(version: version, url: URL(string: "https://x.test/releases/\(version)")!)
    }

    private func manager(feed: ReleaseFeed, currentVersion: String = "1.2.0",
                         now: @escaping () -> Date = Date.init) -> UpdateManager {
        UpdateManager(feed: feed, currentVersion: currentVersion, defaults: defaults, now: now)
    }

    func testPublishesANewerRelease() async {
        let feed = StubFeed(.success(update("1.3.0")))
        let m = manager(feed: feed)
        await m.checkIfDue()
        XCTAssertEqual(feed.calls, 1)
        XCTAssertEqual(m.available?.version, "1.3.0")
    }

    func testIgnoresSameOrOlderRelease() async {
        let m = manager(feed: StubFeed(.success(update("1.2.0"))))
        await m.checkIfDue()
        XCTAssertNil(m.available)
    }

    func testDoesNotCheckTwiceWithinTheInterval() async {
        let feed = StubFeed(.success(update("1.3.0")))
        let start = Date()
        let m = manager(feed: feed, now: { start })
        await m.checkIfDue()
        await m.checkIfDue()
        XCTAssertEqual(feed.calls, 1, "second call is inside the interval")
    }

    func testChecksAgainAfterTheInterval() async {
        let feed = StubFeed(.success(update("1.3.0")))
        var clock = Date()
        let m = manager(feed: feed, now: { clock })
        await m.checkIfDue()
        clock = clock.addingTimeInterval(UpdateManager.checkInterval + 1)
        await m.checkIfDue()
        XCTAssertEqual(feed.calls, 2)
    }

    func testClockRollbackTriggersACheck() async {
        let feed = StubFeed(.success(update("1.3.0")))
        var clock = Date()
        let m = manager(feed: feed, now: { clock })
        await m.checkIfDue()
        clock = clock.addingTimeInterval(-30 * 24 * 3600)
        await m.checkIfDue()
        XCTAssertEqual(feed.calls, 2, "a backwards clock must not dodge the check")
    }

    func testNetworkFailureIsSilent() async {
        struct Boom: Error {}
        let m = manager(feed: StubFeed(.failure(Boom())))
        await m.checkIfDue()
        XCTAssertNil(m.available, "a failed check must not surface anything to the user")
    }

    func testDismissedVersionIsNotShownAgain() async {
        let feed = StubFeed(.success(update("1.3.0")))
        var clock = Date()
        let m = manager(feed: feed, now: { clock })
        await m.checkIfDue()
        m.dismiss()
        XCTAssertNil(m.available)

        clock = clock.addingTimeInterval(UpdateManager.checkInterval + 1)
        await m.checkIfDue()
        XCTAssertNil(m.available, "the same version must not nag again")

        feed.result = .success(update("1.4.0"))
        clock = clock.addingTimeInterval(UpdateManager.checkInterval + 1)
        await m.checkIfDue()
        XCTAssertEqual(m.available?.version, "1.4.0", "a later version still surfaces")
    }

    func testDisablingAutomaticChecksStopsThem() async {
        let feed = StubFeed(.success(update("1.3.0")))
        let m = manager(feed: feed)
        m.automaticChecksEnabled = false
        await m.checkIfDue()
        XCTAssertEqual(feed.calls, 0)
        XCTAssertNil(m.available)
    }

    func testAutomaticChecksPreferenceSurvivesRelaunch() async {
        let m = manager(feed: StubFeed(.success(update("1.3.0"))))
        XCTAssertTrue(m.automaticChecksEnabled, "on by default")
        m.automaticChecksEnabled = false
        let relaunched = manager(feed: StubFeed(.success(update("1.3.0"))))
        XCTAssertFalse(relaunched.automaticChecksEnabled)
    }

    func testManualCheckIgnoresTheInterval() async {
        let feed = StubFeed(.success(update("1.3.0")))
        let start = Date()
        let m = manager(feed: feed, now: { start })
        await m.checkIfDue()
        await m.checkNow()
        XCTAssertEqual(feed.calls, 2, "an explicit check always runs")
    }

    func testManualCheckWorksEvenWithAutomaticChecksOff() async {
        let feed = StubFeed(.success(update("1.3.0")))
        let m = manager(feed: feed)
        m.automaticChecksEnabled = false
        await m.checkNow()
        XCTAssertEqual(feed.calls, 1, "the user asked for it explicitly")
        XCTAssertEqual(m.available?.version, "1.3.0")
    }
}
