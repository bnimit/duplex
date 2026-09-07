# Own-Identity Instances (Duplex 1.2) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make every Duplex instance a copy-on-write clone of the target app with its own bundle identity, so the original launches alongside instances and OAuth callbacks reach the right instance.

**Architecture:** `WrapperGenerator` clones the target bundle (clonefile), patches its Info.plist (`InstancePlist`), strips quarantine, drops the provisioning profile, adds `duplex-launcher`, and ad-hoc signs helpers, Mach-O executables and the outer bundle (never `--deep`). The launcher execs the clone's own copy of the app binary with `--user-data-dir` and `--use-mock-keychain`, and regenerates the clone in place when the original app's version has changed. `AppState` migrates 1.1 wrappers, runs generation off the main actor, and refuses to edit or delete a running instance.

**Tech Stack:** Swift 5.10 package (macOS 13+), SwiftUI, XCTest, `/usr/bin/codesign`, `clonefile(2)`, `flock(2)`.

Spec: `docs/superpowers/specs/2026-09-07-own-identity-instances-design.md`.

## Global Constraints

- No em dashes anywhere: code comments, README, site copy, commit messages.
- macOS 13.0 deployment target (`Package.swift` platforms `.macOS(.v13)`).
- Duplex's own bundle id `com.duplex-app.Duplex` stays outside the `com.duplex.` instance prefix.
- Never modify `/Applications/Claude.app` or any real installed app. Tests use fixture bundles in temp dirs only.
- Data dir stays `~/Library/Application Support/Duplex/<slug>/data`.
- Keep `CFBundleName` and `ElectronAsarIntegrity` from the target plist untouched in clones.
- Ad-hoc signing only, never `codesign --deep` on the clone.
- Run `swift test` before every commit; all tests must pass (the `DodoTestModeIntegration` tests skip without `DODO_TEST_KEY`, that is expected).
- Commit after each task with the message given.

## File Structure

| File | Responsibility |
|---|---|
| `Sources/DuplexKit/DuplexPlistKey.swift` (modify) | Adds `targetExecutable`, `formatVersion`, `sourceVersion` keys, `currentFormatVersion` |
| `Sources/DuplexKit/InstancePlist.swift` (create) | Pure plist patching and source-version formatting; replaces `WrapperPlist.swift` (delete) |
| `Sources/DuplexKit/LauncherLogic.swift` (modify) | `LauncherConfig` gains executable, name, sourceVersion; `needsResync`; mock keychain arg |
| `Sources/DuplexKit/BundleCloner.swift` (create) | clonefile with copy fallback, quarantine stripping, Mach-O detection |
| `Sources/DuplexKit/Codesigner.swift` (create) | Ad-hoc sign one item, describe a signature (tests) |
| `Sources/DuplexKit/WrapperGenerator.swift` (modify) | Build step becomes clone + patch + sign; stage-and-swap unchanged |
| `Sources/DuplexKit/InstanceStore.swift` (modify) | `Instance` gains `formatVersion`, `sourceVersion`, `bundleID` |
| `Sources/DuplexKit/InstanceRuntime.swift` (create) | Is an instance running; quit it |
| `Sources/duplex-launcher/main.swift` (modify) | Drift check with lock, self-regeneration, exec sibling binary |
| `Sources/Duplex/AppState.swift` (modify) | Async create with `isBusy`, migration, running guard, remove `launchOriginal` |
| `Sources/Duplex/InstanceListView.swift`, `InstanceEditorSheet.swift` (modify) | Busy indicator, guard alerts, migration alert, async submit |
| `Tests/DuplexKitTests/FixtureFactory.swift` (modify) | Versioned fixture apps with helper, native executable, provisioning profile, icon name, document types |
| `Tests/DuplexKitTests/InstancePlistTests.swift`, `BundleClonerTests.swift`, `CodesignerTests.swift`, `InstanceRuntimeTests.swift` (create); `WrapperPlistTests.swift` (delete); others (modify) | Tests |
| `scripts/build-app.sh`, `README.md`, `packaging/duplex.rb` (modify); site repo `duplex/index.html`, `terms/index.html` | Version 1.2.0 and documentation |

---

### Task 1: Plist keys and `InstancePlist`

**Files:**
- Modify: `Sources/DuplexKit/DuplexPlistKey.swift`
- Create: `Sources/DuplexKit/InstancePlist.swift`
- Delete: `Sources/DuplexKit/WrapperPlist.swift`, `Tests/DuplexKitTests/WrapperPlistTests.swift`
- Modify: `Tests/DuplexKitTests/FixtureFactory.swift`, `Tests/DuplexKitTests/WrapperGeneratorTests.swift:179-194`, `Tests/DuplexKitTests/InstanceStoreTests.swift:62-75`
- Create: `Tests/DuplexKitTests/InstancePlistTests.swift`

**Interfaces:**
- Produces: `DuplexPlistKey.targetExecutable`, `.formatVersion`, `.sourceVersion` (String keys), `DuplexPlistKey.currentFormatVersion: Int = 2`.
- Produces: `InstancePlist.launcherExecutable = "duplex-launcher"`, `InstancePlist.iconFile = "icon.icns"`, `InstancePlist.patch(_ original: [String: Any], spec: InstanceSpec) -> [String: Any]`, `InstancePlist.sourceVersion(of plist: [String: Any]) -> String?`, `InstancePlist.sourceVersion(ofBundleAt url: URL) -> String?`.
- Produces: `FixtureFactory.legacyDuplexPlist(spec: InstanceSpec) -> [String: Any]`; fixture apps now carry `CFBundleShortVersionString "1.0"` and `CFBundleVersion "100"`.

- [ ] **Step 1: Extend the plist keys**

Replace `Sources/DuplexKit/DuplexPlistKey.swift` with:

```swift
public enum DuplexPlistKey {
    public static let targetBundleID = "DuplexTargetBundleID"
    public static let targetPath = "DuplexTargetPath"
    /// CFBundleExecutable of the target app, i.e. the binary that sits next to the launcher in a clone.
    public static let targetExecutable = "DuplexTargetExecutable"
    public static let instanceSlug = "DuplexInstanceSlug"
    public static let instanceName = "DuplexInstanceName"
    /// 1 (or absent): 1.1 thin wrapper. 2: cloned app with its own identity.
    public static let formatVersion = "DuplexFormatVersion"
    /// Version of the target app the clone was made from; see InstancePlist.sourceVersion(of:).
    public static let sourceVersion = "DuplexSourceVersion"
    public static let currentFormatVersion = 2
    public static let bundleIDPrefix = "com.duplex."
}
```

- [ ] **Step 2: Add version keys and the legacy plist helper to the fixture factory**

In `Tests/DuplexKitTests/FixtureFactory.swift`, add `import DuplexKit` under `import Foundation`, then change the plist literal in `makeFakeApp` to:

```swift
        var plist: [String: Any] = [
            "CFBundleIdentifier": bundleID,
            "CFBundleName": name,
            "CFBundleExecutable": name,
            "CFBundlePackageType": "APPL",
            "CFBundleShortVersionString": "1.0",
            "CFBundleVersion": "100",
        ]
```

and add this static function inside the enum:

```swift
    /// A 1.1-format wrapper plist (no DuplexFormatVersion) for legacy-detection and staging tests.
    static func legacyDuplexPlist(spec: InstanceSpec) -> [String: Any] {
        [
            "CFBundleIdentifier": DuplexPlistKey.bundleIDPrefix + spec.slug,
            "CFBundleName": spec.name,
            "CFBundleExecutable": "duplex-launcher",
            DuplexPlistKey.targetBundleID: spec.target.bundleID,
            DuplexPlistKey.targetPath: spec.target.url.path,
            DuplexPlistKey.instanceSlug: spec.slug,
            DuplexPlistKey.instanceName: spec.name,
        ]
    }
```

- [ ] **Step 3: Write the failing tests**

Create `Tests/DuplexKitTests/InstancePlistTests.swift`:

```swift
import XCTest
@testable import DuplexKit

final class InstancePlistTests: XCTestCase {
    private let target = TargetApp(
        url: URL(fileURLWithPath: "/Applications/Fake.app"),
        bundleID: "com.x.fake", name: "Fake", executable: "Fake", urlSchemes: ["fake"])
    private var spec: InstanceSpec { InstanceSpec(name: "Fake Work", slug: "fake-work", target: target) }

    private var original: [String: Any] {
        [
            "CFBundleIdentifier": "com.x.fake",
            "CFBundleName": "Fake",
            "CFBundleDisplayName": "Fake",
            "CFBundleExecutable": "Fake",
            "CFBundleIconFile": "electron.icns",
            "CFBundleIconName": "Fake",
            "CFBundleShortVersionString": "1.2.3",
            "CFBundleVersion": "456",
            "CFBundleDocumentTypes": [["CFBundleTypeName": "Thing"]],
            "UTExportedTypeDeclarations": [["UTTypeIdentifier": "com.x.thing"]],
            "CFBundleURLTypes": [["CFBundleURLName": "Fake", "CFBundleURLSchemes": ["fake"]]],
            "ElectronAsarIntegrity": ["Resources/app.asar": ["algorithm": "SHA256", "hash": "abc"]],
            "LSMinimumSystemVersion": "12.0",
        ]
    }

    func testPatchesIdentityKeys() {
        let p = InstancePlist.patch(original, spec: spec)
        XCTAssertEqual(p["CFBundleIdentifier"] as? String, "com.duplex.fake-work")
        XCTAssertEqual(p["CFBundleDisplayName"] as? String, "Fake Work")
        XCTAssertEqual(p["CFBundleExecutable"] as? String, "duplex-launcher")
        XCTAssertEqual(p["CFBundleIconFile"] as? String, "icon.icns")
    }

    func testKeepsElectronCriticalKeys() {
        let p = InstancePlist.patch(original, spec: spec)
        XCTAssertEqual(p["CFBundleName"] as? String, "Fake", "Electron derives helper app names from CFBundleName")
        XCTAssertNotNil(p["ElectronAsarIntegrity"])
        XCTAssertEqual(p["LSMinimumSystemVersion"] as? String, "12.0")
        XCTAssertEqual(p["CFBundleShortVersionString"] as? String, "1.2.3")
        let urlTypes = p["CFBundleURLTypes"] as? [[String: Any]]
        XCTAssertEqual(urlTypes?.first?["CFBundleURLSchemes"] as? [String], ["fake"])
    }

    func testRemovesKeysThatWouldLeakOrClutter() {
        let p = InstancePlist.patch(original, spec: spec)
        XCTAssertNil(p["CFBundleIconName"], "an Assets.car icon name would override icon.icns")
        XCTAssertNil(p["CFBundleDocumentTypes"])
        XCTAssertNil(p["UTExportedTypeDeclarations"])
    }

    func testAddsDuplexKeys() {
        let p = InstancePlist.patch(original, spec: spec)
        XCTAssertEqual(p[DuplexPlistKey.targetBundleID] as? String, "com.x.fake")
        XCTAssertEqual(p[DuplexPlistKey.targetPath] as? String, "/Applications/Fake.app")
        XCTAssertEqual(p[DuplexPlistKey.targetExecutable] as? String, "Fake")
        XCTAssertEqual(p[DuplexPlistKey.instanceSlug] as? String, "fake-work")
        XCTAssertEqual(p[DuplexPlistKey.instanceName] as? String, "Fake Work")
        XCTAssertEqual(p[DuplexPlistKey.formatVersion] as? Int, 2)
        XCTAssertEqual(p[DuplexPlistKey.sourceVersion] as? String, "1.2.3 (456)")
        XCTAssertNoThrow(try PropertyListSerialization.data(fromPropertyList: p, format: .xml, options: 0))
    }

    func testSourceVersionCombinations() {
        XCTAssertEqual(InstancePlist.sourceVersion(of: ["CFBundleShortVersionString": "1.0", "CFBundleVersion": "7"]), "1.0 (7)")
        XCTAssertEqual(InstancePlist.sourceVersion(of: ["CFBundleShortVersionString": "1.0"]), "1.0")
        XCTAssertEqual(InstancePlist.sourceVersion(of: ["CFBundleVersion": "7"]), "(7)")
        XCTAssertNil(InstancePlist.sourceVersion(of: [:]))
    }

    func testSourceVersionOfBundleOnDisk() throws {
        let tmp = try FixtureFactory.tempDir(name)
        defer { try? FileManager.default.removeItem(at: tmp) }
        let app = try FixtureFactory.makeFakeApp(named: "Fake", bundleID: "com.x.fake", electron: true, in: tmp)
        XCTAssertEqual(InstancePlist.sourceVersion(ofBundleAt: app), "1.0 (100)")
        XCTAssertNil(InstancePlist.sourceVersion(ofBundleAt: tmp.appendingPathComponent("Nope.app")))
    }
}
```

- [ ] **Step 4: Run the new tests to verify they fail**

Run: `swift test --filter InstancePlistTests 2>&1 | tail -5`
Expected: build error, `InstancePlist` not found.

- [ ] **Step 5: Implement `InstancePlist`**

Create `Sources/DuplexKit/InstancePlist.swift`:

```swift
import Foundation

/// Turns a target app's own Info.plist into an instance plist. Pure: no filesystem access
/// except the one convenience reader at the bottom.
public enum InstancePlist {
    public static let launcherExecutable = "duplex-launcher"
    public static let iconFile = "icon.icns"

    /// Keys removed from clones: an Assets.car icon name would beat icon.icns in Finder, and
    /// document/UTI declarations would add "Open With" entries for every instance.
    static let removedKeys = [
        "CFBundleIconName", "CFBundleDocumentTypes",
        "UTExportedTypeDeclarations", "UTImportedTypeDeclarations",
    ]

    /// "<CFBundleShortVersionString> (<CFBundleVersion>)" of the target so a change to either
    /// triggers a re-sync. nil when the plist has neither.
    public static func sourceVersion(of plist: [String: Any]) -> String? {
        let short = plist["CFBundleShortVersionString"] as? String
        let build = plist["CFBundleVersion"] as? String
        switch (short, build) {
        case (nil, nil): return nil
        case (let s?, nil): return s
        case (nil, let b?): return "(\(b))"
        case (let s?, let b?): return "\(s) (\(b))"
        }
    }

    public static func sourceVersion(ofBundleAt url: URL) -> String? {
        let plistURL = url.appendingPathComponent("Contents/Info.plist")
        guard let data = try? Data(contentsOf: plistURL),
              let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any]
        else { return nil }
        return sourceVersion(of: plist)
    }

    /// Changes only identity, icon, executable and the Duplex bookkeeping keys. CFBundleName
    /// stays (Electron derives "<CFBundleName> Helper.app" from it) and so does
    /// ElectronAsarIntegrity.
    public static func patch(_ original: [String: Any], spec: InstanceSpec) -> [String: Any] {
        var plist = original
        plist["CFBundleIdentifier"] = DuplexPlistKey.bundleIDPrefix + spec.slug
        plist["CFBundleDisplayName"] = spec.name
        plist["CFBundleExecutable"] = launcherExecutable
        plist["CFBundleIconFile"] = iconFile
        for key in removedKeys { plist.removeValue(forKey: key) }
        plist[DuplexPlistKey.targetBundleID] = spec.target.bundleID
        plist[DuplexPlistKey.targetPath] = spec.target.url.path
        plist[DuplexPlistKey.targetExecutable] = spec.target.executable
        plist[DuplexPlistKey.instanceSlug] = spec.slug
        plist[DuplexPlistKey.instanceName] = spec.name
        plist[DuplexPlistKey.formatVersion] = DuplexPlistKey.currentFormatVersion
        if let version = sourceVersion(of: original) {
            plist[DuplexPlistKey.sourceVersion] = version
        }
        return plist
    }
}
```

- [ ] **Step 6: Remove `WrapperPlist` and fix its two remaining callers**

Delete `Sources/DuplexKit/WrapperPlist.swift` and `Tests/DuplexKitTests/WrapperPlistTests.swift`.

In `Tests/DuplexKitTests/WrapperGeneratorTests.swift`, inside `testStaleStagingLeftoverDoesNotBreakGenerate`, replace
`let plist = WrapperPlist.plist(for: spec)` with
`let plist = FixtureFactory.legacyDuplexPlist(spec: spec)`.

In `Tests/DuplexKitTests/InstanceStoreTests.swift`, inside `testScanIgnoresHiddenStagingBundles`, replace
`WrapperPlist.plist(for: spec)` with `FixtureFactory.legacyDuplexPlist(spec: spec)`.

`Sources/DuplexKit/WrapperGenerator.swift` still calls `WrapperPlist.plist(for: spec)` at line 75. The package must keep building until Task 4 rewrites the generator, so add this temporary private helper at the bottom of `WrapperGenerator.swift` (Task 4 deletes it):

```swift
// Temporary until the clone-based build lands: the 1.1 thin-wrapper plist.
private enum LegacyWrapperPlist {
    static func plist(for spec: InstanceSpec) -> [String: Any] {
        var plist: [String: Any] = [
            "CFBundleIdentifier": DuplexPlistKey.bundleIDPrefix + spec.slug,
            "CFBundleName": spec.name,
            "CFBundleDisplayName": spec.name,
            "CFBundleExecutable": "duplex-launcher",
            "CFBundlePackageType": "APPL",
            "CFBundleIconFile": "icon",
            "CFBundleShortVersionString": "1.0",
            "CFBundleVersion": "1",
            "LSMinimumSystemVersion": "13.0",
            "NSHighResolutionCapable": true,
            DuplexPlistKey.targetBundleID: spec.target.bundleID,
            DuplexPlistKey.targetPath: spec.target.url.path,
            DuplexPlistKey.instanceSlug: spec.slug,
            DuplexPlistKey.instanceName: spec.name,
        ]
        if !spec.target.urlSchemes.isEmpty {
            plist["CFBundleURLTypes"] = [[
                "CFBundleURLName": spec.name,
                "CFBundleURLSchemes": spec.target.urlSchemes,
            ] as [String: Any]]
        }
        return plist
    }
}
```

and change line 75 to `fromPropertyList: LegacyWrapperPlist.plist(for: spec), format: .xml, options: 0)`.

- [ ] **Step 7: Run all tests**

Run: `swift test 2>&1 | tail -5`
Expected: all pass (InstancePlistTests 6 new tests green; total goes from 82 to 86 after removing 2 and adding 6).

- [ ] **Step 8: Commit**

```bash
git add -A Sources Tests
git commit -m "feat(kit): InstancePlist patches a target plist into an instance plist"
```

---

### Task 2: `LauncherLogic` for clones

**Files:**
- Modify: `Sources/DuplexKit/LauncherLogic.swift`
- Modify: `Tests/DuplexKitTests/LauncherLogicTests.swift`

**Interfaces:**
- Produces: `LauncherConfig(targetBundleID:targetPath:targetExecutable:slug:name:sourceVersion:)` with `targetExecutable: String?`, `name: String` (defaults to slug), `sourceVersion: String?`.
- Produces: `LauncherLogic.needsResync(recorded: String?, installed: String?) -> Bool`.
- Changes: `LauncherLogic.execArguments` now returns `[exe, "--user-data-dir=...", "--use-mock-keychain"]`.

- [ ] **Step 1: Update and add tests**

In `Tests/DuplexKitTests/LauncherLogicTests.swift` replace `testConfigParsing` and `testExecArguments` and add the new tests:

```swift
    func testConfigParsing() {
        let info: [String: Any] = [
            DuplexPlistKey.targetBundleID: "com.x.fake",
            DuplexPlistKey.targetPath: "/Applications/Fake.app",
            DuplexPlistKey.targetExecutable: "Fake",
            DuplexPlistKey.instanceSlug: "fake-work",
            DuplexPlistKey.instanceName: "Fake Work",
            DuplexPlistKey.sourceVersion: "1.0 (100)",
        ]
        XCTAssertEqual(
            LauncherLogic.config(from: info),
            LauncherConfig(targetBundleID: "com.x.fake", targetPath: "/Applications/Fake.app",
                           targetExecutable: "Fake", slug: "fake-work", name: "Fake Work",
                           sourceVersion: "1.0 (100)"))
    }

    func testConfigParsingLegacyWrapperHasNoCloneKeys() {
        let info: [String: Any] = [
            DuplexPlistKey.targetBundleID: "com.x.fake",
            DuplexPlistKey.targetPath: "/Applications/Fake.app",
            DuplexPlistKey.instanceSlug: "fake-work",
        ]
        let config = LauncherLogic.config(from: info)
        XCTAssertEqual(config?.slug, "fake-work")
        XCTAssertEqual(config?.name, "fake-work", "name falls back to the slug")
        XCTAssertNil(config?.targetExecutable)
        XCTAssertNil(config?.sourceVersion)
    }

    func testExecArguments() {
        let args = LauncherLogic.execArguments(
            targetExecutable: "/Applications/Fake Work.app/Contents/MacOS/Fake",
            dataDir: URL(fileURLWithPath: "/tmp/h/data"))
        XCTAssertEqual(args, ["/Applications/Fake Work.app/Contents/MacOS/Fake",
                              "--user-data-dir=/tmp/h/data",
                              "--use-mock-keychain"])
    }

    func testNeedsResync() {
        XCTAssertTrue(LauncherLogic.needsResync(recorded: "1.0 (100)", installed: "1.1 (101)"))
        XCTAssertFalse(LauncherLogic.needsResync(recorded: "1.0 (100)", installed: "1.0 (100)"))
        XCTAssertFalse(LauncherLogic.needsResync(recorded: nil, installed: "1.0 (100)"), "legacy wrapper: nothing recorded")
        XCTAssertFalse(LauncherLogic.needsResync(recorded: "1.0 (100)", installed: nil), "target plist unreadable: leave it")
        XCTAssertFalse(LauncherLogic.needsResync(recorded: nil, installed: nil))
    }
```

- [ ] **Step 2: Run to verify failure**

Run: `swift test --filter LauncherLogicTests 2>&1 | tail -5`
Expected: build error (extra init arguments, `needsResync` missing).

- [ ] **Step 3: Implement**

Replace `Sources/DuplexKit/LauncherLogic.swift` with:

```swift
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
```

- [ ] **Step 4: Run tests**

Run: `swift test 2>&1 | tail -5`
Expected: all pass. (`EndToEndTests` still passes: it only checks that `--user-data-dir` is contained.)

- [ ] **Step 5: Commit**

```bash
git add -A Sources Tests
git commit -m "feat(kit): launcher config carries executable, name and source version; mock keychain switch"
```

---

### Task 3: `BundleCloner` and `Codesigner`

**Files:**
- Create: `Sources/DuplexKit/BundleCloner.swift`, `Sources/DuplexKit/Codesigner.swift`
- Create: `Tests/DuplexKitTests/BundleClonerTests.swift`, `Tests/DuplexKitTests/CodesignerTests.swift`

**Interfaces:**
- Produces: `BundleCloner.clone(_ source: URL, to destination: URL) throws`, `BundleCloner.stripQuarantine(at root: URL)`, `BundleCloner.isMachO(_ url: URL) -> Bool`, `BundleCloner.machOExecutables(in dir: URL) -> [URL]`.
- Produces: `Codesigner.adhocSign(_ url: URL) throws` (throws `WrapperGeneratorError.codesignFailed`), `Codesigner.signatureKind(_ url: URL) -> String?` returning `"adhoc"`, `"signed"`, or nil when unsigned.

- [ ] **Step 1: Write failing tests**

Create `Tests/DuplexKitTests/BundleClonerTests.swift`:

```swift
import XCTest
@testable import DuplexKit

final class BundleClonerTests: XCTestCase {
    var tmp: URL!
    let fm = FileManager.default
    override func setUpWithError() throws { tmp = try FixtureFactory.tempDir(name) }
    override func tearDownWithError() throws { try? fm.removeItem(at: tmp) }

    private func makeTree() throws -> URL {
        let src = tmp.appendingPathComponent("src")
        try fm.createDirectory(at: src.appendingPathComponent("sub"), withIntermediateDirectories: true)
        try "one".write(to: src.appendingPathComponent("sub/a.txt"), atomically: true, encoding: .utf8)
        return src
    }

    func testCloneProducesIndependentCopy() throws {
        let src = try makeTree()
        let dst = tmp.appendingPathComponent("dst")
        try BundleCloner.clone(src, to: dst)
        XCTAssertEqual(try String(contentsOf: dst.appendingPathComponent("sub/a.txt"), encoding: .utf8), "one")
        try "two".write(to: dst.appendingPathComponent("sub/a.txt"), atomically: true, encoding: .utf8)
        XCTAssertEqual(try String(contentsOf: src.appendingPathComponent("sub/a.txt"), encoding: .utf8), "one",
                       "writing to the clone must not touch the source")
    }

    func testCloneRefusesExistingDestination() throws {
        let src = try makeTree()
        let dst = tmp.appendingPathComponent("dst")
        try fm.createDirectory(at: dst, withIntermediateDirectories: true)
        XCTAssertThrowsError(try BundleCloner.clone(src, to: dst))
    }

    func testStripQuarantineRemovesAttributeEverywhere() throws {
        let src = try makeTree()
        let file = src.appendingPathComponent("sub/a.txt")
        let value = "0083;00000000;Safari;"
        for path in [src.path, file.path] {
            XCTAssertEqual(setxattr(path, "com.apple.quarantine", value, value.utf8.count, 0, 0), 0)
        }
        BundleCloner.stripQuarantine(at: src)
        for path in [src.path, file.path] {
            XCTAssertEqual(getxattr(path, "com.apple.quarantine", nil, 0, 0, 0), -1, "\(path) still quarantined")
        }
    }

    func testIsMachO() throws {
        XCTAssertTrue(BundleCloner.isMachO(URL(fileURLWithPath: "/bin/ls")))
        let script = tmp.appendingPathComponent("s.sh")
        try "#!/bin/bash\necho hi\n".write(to: script, atomically: true, encoding: .utf8)
        XCTAssertFalse(BundleCloner.isMachO(script))
        let empty = tmp.appendingPathComponent("empty")
        try Data().write(to: empty)
        XCTAssertFalse(BundleCloner.isMachO(empty))
        XCTAssertFalse(BundleCloner.isMachO(tmp.appendingPathComponent("missing")))
    }

    func testMachOExecutablesListsOnlyMachOFiles() throws {
        let dir = tmp.appendingPathComponent("MacOS")
        try fm.createDirectory(at: dir.appendingPathComponent("subdir"), withIntermediateDirectories: true)
        try fm.copyItem(at: URL(fileURLWithPath: "/bin/ls"), to: dir.appendingPathComponent("native"))
        try "#!/bin/bash\n".write(to: dir.appendingPathComponent("script"), atomically: true, encoding: .utf8)
        XCTAssertEqual(BundleCloner.machOExecutables(in: dir).map(\.lastPathComponent), ["native"])
        XCTAssertEqual(BundleCloner.machOExecutables(in: tmp.appendingPathComponent("nope")), [])
    }
}
```

Create `Tests/DuplexKitTests/CodesignerTests.swift`:

```swift
import XCTest
@testable import DuplexKit

final class CodesignerTests: XCTestCase {
    var tmp: URL!
    override func setUpWithError() throws { tmp = try FixtureFactory.tempDir(name) }
    override func tearDownWithError() throws { try? FileManager.default.removeItem(at: tmp) }

    func testAdhocSignReplacesSignature() throws {
        let copy = tmp.appendingPathComponent("ls")
        try FileManager.default.copyItem(at: URL(fileURLWithPath: "/bin/ls"), to: copy)
        XCTAssertEqual(Codesigner.signatureKind(copy), "signed", "Apple's own signature before re-signing")
        try Codesigner.adhocSign(copy)
        XCTAssertEqual(Codesigner.signatureKind(copy), "adhoc")
    }

    func testSignatureKindOfUnsignedFileIsNil() throws {
        let script = tmp.appendingPathComponent("s.sh")
        try "#!/bin/bash\n".write(to: script, atomically: true, encoding: .utf8)
        XCTAssertNil(Codesigner.signatureKind(script))
    }

    func testAdhocSignFailureThrows() {
        XCTAssertThrowsError(try Codesigner.adhocSign(tmp.appendingPathComponent("missing"))) { error in
            guard case WrapperGeneratorError.codesignFailed = error else { return XCTFail("wrong error: \(error)") }
        }
    }
}
```

- [ ] **Step 2: Run to verify failure**

Run: `swift test --filter 'BundleClonerTests|CodesignerTests' 2>&1 | tail -5`
Expected: build error, types not found.

- [ ] **Step 3: Implement `BundleCloner`**

Create `Sources/DuplexKit/BundleCloner.swift`:

```swift
import Foundation

public enum BundleClonerError: Error, LocalizedError {
    case destinationExists(String)
    public var errorDescription: String? {
        switch self {
        case .destinationExists(let path): return "\(path) already exists."
        }
    }
}

/// Filesystem primitives for building an instance out of a target app bundle.
public enum BundleCloner {
    /// Copy-on-write clone of a whole tree via clonefile(2): sub-second and shares disk blocks
    /// with the source. Falls back to a regular recursive copy when the volume refuses
    /// (different volume, non-APFS).
    public static func clone(_ source: URL, to destination: URL) throws {
        if FileManager.default.fileExists(atPath: destination.path) {
            throw BundleClonerError.destinationExists(destination.path)
        }
        if clonefile(source.path, destination.path, 0) == 0 { return }
        try FileManager.default.copyItem(at: source, to: destination)
    }

    /// Removes com.apple.quarantine from every item in the tree. A clone inherits the
    /// original's attributes, and Gatekeeper refuses a quarantined ad-hoc bundle. Errors are
    /// ignored: most files simply do not carry the attribute.
    public static func stripQuarantine(at root: URL) {
        let name = "com.apple.quarantine"
        removexattr(root.path, name, XATTR_NOFOLLOW)
        guard let enumerator = FileManager.default.enumerator(
            at: root, includingPropertiesForKeys: nil, options: []) else { return }
        for case let url as URL in enumerator {
            removexattr(url.path, name, XATTR_NOFOLLOW)
        }
    }

    /// True when the file starts with a Mach-O or fat-binary magic number.
    public static func isMachO(_ url: URL) -> Bool {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return false }
        defer { try? handle.close() }
        guard let data = try? handle.read(upToCount: 4), data.count == 4 else { return false }
        let magic = data.withUnsafeBytes { $0.loadUnaligned(as: UInt32.self) }
        let known: [UInt32] = [0xfeedfacf, 0xcffaedfe, 0xfeedface, 0xcefaedfe, 0xcafebabe, 0xbebafeca]
        return known.contains(magic)
    }

    /// Regular Mach-O files directly inside `dir` (not recursive), sorted by name. Scripts and
    /// other non-Mach-O files are left out because they cannot carry an embedded signature.
    public static func machOExecutables(in dir: URL) -> [URL] {
        let items = (try? FileManager.default.contentsOfDirectory(
            at: dir, includingPropertiesForKeys: [.isRegularFileKey], options: [])) ?? []
        return items
            .filter { url in
                let regular = (try? url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) ?? false
                return regular && isMachO(url)
            }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
    }
}
```

- [ ] **Step 4: Implement `Codesigner`**

Create `Sources/DuplexKit/Codesigner.swift`:

```swift
import Foundation

/// Thin wrapper over /usr/bin/codesign. Ad-hoc only, one item at a time, never --deep: a
/// clone's helpers and binaries are signed explicitly, innermost first, and its frameworks keep
/// the vendor's signature.
public enum Codesigner {
    public static func adhocSign(_ url: URL) throws {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/codesign")
        p.arguments = ["--force", "-s", "-", url.path]
        p.standardOutput = FileHandle.nullDevice
        p.standardError = FileHandle.nullDevice
        try p.run()
        p.waitUntilExit()
        guard p.terminationStatus == 0 else { throw WrapperGeneratorError.codesignFailed(p.terminationStatus) }
    }

    /// "adhoc" for an ad-hoc signature, "signed" for any other valid signature, nil when the
    /// item is unsigned or unreadable. Parses `codesign -dv`, which reports on stderr.
    public static func signatureKind(_ url: URL) -> String? {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/codesign")
        p.arguments = ["-dv", url.path]
        let pipe = Pipe()
        p.standardOutput = FileHandle.nullDevice
        p.standardError = pipe
        guard (try? p.run()) != nil else { return nil }
        let output = String(decoding: pipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        p.waitUntilExit()
        guard p.terminationStatus == 0 else { return nil }
        return output.contains("Signature=adhoc") ? "adhoc" : "signed"
    }
}
```

- [ ] **Step 5: Run tests**

Run: `swift test 2>&1 | tail -5`
Expected: all pass.

- [ ] **Step 6: Commit**

```bash
git add -A Sources Tests
git commit -m "feat(kit): BundleCloner (clonefile, quarantine, Mach-O) and Codesigner"
```

---

### Task 4: Clone-based `WrapperGenerator`

**Files:**
- Modify: `Tests/DuplexKitTests/FixtureFactory.swift`
- Modify: `Sources/DuplexKit/WrapperGenerator.swift`
- Modify: `Tests/DuplexKitTests/WrapperGeneratorTests.swift`

**Interfaces:**
- Consumes: `InstancePlist.patch`, `InstancePlist.launcherExecutable`, `InstancePlist.iconFile` (Task 1); `BundleCloner.*`, `Codesigner.*` (Task 3).
- Produces: `WrapperGenerator(launcherBinary:).generate(spec:icon:outputDir:) -> URL` unchanged in signature; output bundle is now a clone with `Contents/MacOS/<target executable>`, `Contents/MacOS/duplex-launcher`, `Contents/Resources/icon.icns`, patched plist. New error case `WrapperGeneratorError.unreadablePlist(String)`.
- Produces: `FixtureFactory.makeFakeApp(named:bundleID:electron:schemes:helper:nativeExecutable:provisionProfile:iconName:documentTypes:in:)` (new params all default to off) and `FixtureFactory.setVersion(of app: URL, short: String, build: String) throws`. The fixture executable script now records `"$0 $@"` (the path it ran from, then its arguments).

- [ ] **Step 1: Extend the fixture factory**

Replace `makeFakeApp` in `Tests/DuplexKitTests/FixtureFactory.swift` with:

```swift
    /// Builds a minimal fake .app bundle. If electron: true, adds
    /// Contents/Frameworks/Electron Framework.framework/.
    /// The executable is a bash script that records "$0 $@" (its own path, then argv) to
    /// <bundle-parent>/args.txt, so tests can see where it ran from and with which flags.
    /// Optional extras mirror what real Electron apps ship: a helper app and a second Mach-O
    /// in MacOS (both copies of /bin/ls so codesign works), a provisioning profile, an
    /// Assets.car icon name, and document types.
    @discardableResult
    static func makeFakeApp(
        named name: String,
        bundleID: String,
        electron: Bool,
        schemes: [String] = [],
        helper: Bool = false,
        nativeExecutable: Bool = false,
        provisionProfile: Bool = false,
        iconName: String? = nil,
        documentTypes: Bool = false,
        in dir: URL
    ) throws -> URL {
        let fm = FileManager.default
        let app = dir.appendingPathComponent("\(name).app")
        let contents = app.appendingPathComponent("Contents")
        let macos = contents.appendingPathComponent("MacOS")
        try fm.createDirectory(at: macos, withIntermediateDirectories: true)

        var plist: [String: Any] = [
            "CFBundleIdentifier": bundleID,
            "CFBundleName": name,
            "CFBundleExecutable": name,
            "CFBundlePackageType": "APPL",
            "CFBundleShortVersionString": "1.0",
            "CFBundleVersion": "100",
        ]
        if !schemes.isEmpty {
            plist["CFBundleURLTypes"] = [["CFBundleURLName": name, "CFBundleURLSchemes": schemes]]
        }
        if let iconName { plist["CFBundleIconName"] = iconName }
        if documentTypes {
            plist["CFBundleDocumentTypes"] = [["CFBundleTypeName": "Thing", "CFBundleTypeExtensions": ["thing"]]]
        }
        let plistData = try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
        try plistData.write(to: contents.appendingPathComponent("Info.plist"))

        let script = "#!/bin/bash\necho \"$0 $@\" > \"$(dirname \"$0\")/../../../args.txt\"\n"
        let exec = macos.appendingPathComponent(name)
        try script.write(to: exec, atomically: true, encoding: .utf8)
        try fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: exec.path)

        if electron {
            let fw = contents.appendingPathComponent("Frameworks/Electron Framework.framework")
            try fm.createDirectory(at: fw, withIntermediateDirectories: true)
        }
        if helper {
            let helperApp = contents.appendingPathComponent("Frameworks/\(name) Helper.app")
            let helperMacOS = helperApp.appendingPathComponent("Contents/MacOS")
            try fm.createDirectory(at: helperMacOS, withIntermediateDirectories: true)
            let helperPlist: [String: Any] = [
                "CFBundleIdentifier": bundleID + ".helper",
                "CFBundleName": "\(name) Helper",
                "CFBundleExecutable": "\(name) Helper",
                "CFBundlePackageType": "APPL",
            ]
            try PropertyListSerialization.data(fromPropertyList: helperPlist, format: .xml, options: 0)
                .write(to: helperApp.appendingPathComponent("Contents/Info.plist"))
            try fm.copyItem(at: URL(fileURLWithPath: "/bin/ls"),
                            to: helperMacOS.appendingPathComponent("\(name) Helper"))
        }
        if nativeExecutable {
            try fm.copyItem(at: URL(fileURLWithPath: "/bin/ls"), to: macos.appendingPathComponent("\(name)-native"))
        }
        if provisionProfile {
            try Data("fake profile".utf8).write(to: contents.appendingPathComponent("embedded.provisionprofile"))
        }
        return app
    }

    /// Rewrites the version keys of a fixture app, simulating an app update.
    static func setVersion(of app: URL, short: String, build: String) throws {
        let plistURL = app.appendingPathComponent("Contents/Info.plist")
        var plist = try PropertyListSerialization.propertyList(
            from: try Data(contentsOf: plistURL), format: nil) as! [String: Any]
        plist["CFBundleShortVersionString"] = short
        plist["CFBundleVersion"] = build
        try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0).write(to: plistURL)
    }
```

- [ ] **Step 2: Rewrite the generator tests**

In `Tests/DuplexKitTests/WrapperGeneratorTests.swift`:

Replace `makeSpec()` with a version that accepts fixture extras:

```swift
    private func makeSpec(helper: Bool = false, nativeExecutable: Bool = false,
                          provisionProfile: Bool = false, iconName: String? = nil,
                          documentTypes: Bool = false) throws -> InstanceSpec {
        let app = try FixtureFactory.makeFakeApp(
            named: "Fake", bundleID: "com.x.fake", electron: true, schemes: ["fake"],
            helper: helper, nativeExecutable: nativeExecutable, provisionProfile: provisionProfile,
            iconName: iconName, documentTypes: documentTypes, in: tmp)
        return InstanceSpec(name: "Fake Work", slug: "fake-work", target: try AppInspector.inspect(app))
    }

    private func plist(of bundle: URL) throws -> [String: Any] {
        let data = try Data(contentsOf: bundle.appendingPathComponent("Contents/Info.plist"))
        return try PropertyListSerialization.propertyList(from: data, format: nil) as! [String: Any]
    }
```

Replace `testGeneratesCompleteBundle` with:

```swift
    func testGeneratesCompleteBundle() throws {
        let out = tmp.appendingPathComponent("wrappers")
        let wrapper = try generator.generate(spec: try makeSpec(), icon: .badge(.blue), outputDir: out)

        XCTAssertEqual(wrapper.lastPathComponent, "Fake Work.app")
        let fm = FileManager.default
        XCTAssertTrue(fm.fileExists(atPath: wrapper.appendingPathComponent("Contents/PkgInfo").path))
        XCTAssertTrue(fm.fileExists(atPath: wrapper.appendingPathComponent("Contents/Resources/icon.icns").path))
        XCTAssertTrue(fm.isExecutableFile(atPath: wrapper.appendingPathComponent("Contents/MacOS/duplex-launcher").path))
        // The clone carries the target's own binary and frameworks.
        XCTAssertTrue(fm.isExecutableFile(atPath: wrapper.appendingPathComponent("Contents/MacOS/Fake").path))
        XCTAssertTrue(fm.fileExists(atPath: wrapper.appendingPathComponent("Contents/Frameworks/Electron Framework.framework").path))

        let plist = try plist(of: wrapper)
        XCTAssertEqual(plist["CFBundleIdentifier"] as? String, "com.duplex.fake-work")
        XCTAssertEqual(plist["CFBundleDisplayName"] as? String, "Fake Work")
        XCTAssertEqual(plist["CFBundleName"] as? String, "Fake", "kept from the target")
        XCTAssertEqual(plist["CFBundleExecutable"] as? String, "duplex-launcher")
        XCTAssertEqual(plist[DuplexPlistKey.instanceSlug] as? String, "fake-work")
        XCTAssertEqual(plist[DuplexPlistKey.targetExecutable] as? String, "Fake")
        XCTAssertEqual(plist[DuplexPlistKey.formatVersion] as? Int, 2)
        XCTAssertEqual(plist[DuplexPlistKey.sourceVersion] as? String, "1.0 (100)")
    }

    func testTargetIsUntouched() throws {
        let spec = try makeSpec(provisionProfile: true)
        _ = try generator.generate(spec: spec, icon: .badge(.blue), outputDir: tmp.appendingPathComponent("wrappers"))
        let target = try plist(of: spec.target.url)
        XCTAssertEqual(target["CFBundleIdentifier"] as? String, "com.x.fake")
        XCTAssertNil(target[DuplexPlistKey.instanceSlug])
        XCTAssertTrue(FileManager.default.fileExists(
            atPath: spec.target.url.appendingPathComponent("Contents/embedded.provisionprofile").path))
    }

    func testRemovesProvisionProfileAndQuarantine() throws {
        let spec = try makeSpec(provisionProfile: true)
        let value = "0083;00000000;Safari;"
        XCTAssertEqual(setxattr(spec.target.url.path, "com.apple.quarantine", value, value.utf8.count, 0, 0), 0)
        XCTAssertEqual(setxattr(spec.target.url.appendingPathComponent("Contents/MacOS/Fake").path,
                                "com.apple.quarantine", value, value.utf8.count, 0, 0), 0)

        let wrapper = try generator.generate(spec: spec, icon: .badge(.blue), outputDir: tmp.appendingPathComponent("wrappers"))
        XCTAssertFalse(FileManager.default.fileExists(
            atPath: wrapper.appendingPathComponent("Contents/embedded.provisionprofile").path))
        XCTAssertEqual(getxattr(wrapper.path, "com.apple.quarantine", nil, 0, 0, 0), -1)
        XCTAssertEqual(getxattr(wrapper.appendingPathComponent("Contents/MacOS/Fake").path,
                                "com.apple.quarantine", nil, 0, 0, 0), -1)
    }

    func testHelpersAndMachOExecutablesAreAdhocSigned() throws {
        let spec = try makeSpec(helper: true, nativeExecutable: true)
        let wrapper = try generator.generate(spec: spec, icon: .badge(.blue), outputDir: tmp.appendingPathComponent("wrappers"))
        XCTAssertEqual(Codesigner.signatureKind(wrapper.appendingPathComponent("Contents/Frameworks/Fake Helper.app")), "adhoc")
        XCTAssertEqual(Codesigner.signatureKind(wrapper.appendingPathComponent("Contents/MacOS/Fake-native")), "adhoc")
        XCTAssertEqual(Codesigner.signatureKind(wrapper.appendingPathComponent("Contents/MacOS/duplex-launcher")), "adhoc")
        XCTAssertEqual(Codesigner.signatureKind(wrapper), "adhoc")
        // The script main executable of the fixture cannot carry an embedded signature and is skipped.
        XCTAssertNil(Codesigner.signatureKind(wrapper.appendingPathComponent("Contents/MacOS/Fake")))
    }

    func testDropsIconNameAndDocumentTypesKeepsURLTypes() throws {
        let spec = try makeSpec(iconName: "Fake", documentTypes: true)
        let wrapper = try generator.generate(spec: spec, icon: .badge(.blue), outputDir: tmp.appendingPathComponent("wrappers"))
        let plist = try plist(of: wrapper)
        XCTAssertNil(plist["CFBundleIconName"])
        XCTAssertNil(plist["CFBundleDocumentTypes"])
        XCTAssertEqual(plist["CFBundleIconFile"] as? String, "icon.icns")
        let urlTypes = plist["CFBundleURLTypes"] as? [[String: Any]]
        XCTAssertEqual(urlTypes?.first?["CFBundleURLSchemes"] as? [String], ["fake"])
    }
```

Replace `testWrapperIsCodesigned` so it uses strict verification:

```swift
    func testWrapperIsCodesigned() throws {
        let out = tmp.appendingPathComponent("wrappers")
        let wrapper = try generator.generate(spec: try makeSpec(helper: true), icon: .badge(.red), outputDir: out)

        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/codesign")
        p.arguments = ["--verify", "--strict", wrapper.path]
        try p.run()
        p.waitUntilExit()
        XCTAssertEqual(p.terminationStatus, 0, "clone should pass codesign --verify --strict")
    }
```

Leave the other tests as they are (they exercise stage-and-swap, icons and bystander protection, which do not change).

- [ ] **Step 3: Run to verify failure**

Run: `swift test --filter WrapperGeneratorTests 2>&1 | grep -E "error|failed|passed" | head -20`
Expected: new tests fail (`Contents/MacOS/Fake` missing, format version nil, etc.). `testGeneratesCompleteBundle` fails on `CFBundleName` and `DuplexFormatVersion`.

- [ ] **Step 4: Rewrite the generator's build and sign steps**

In `Sources/DuplexKit/WrapperGenerator.swift`:

Add the new error case to `WrapperGeneratorError`:

```swift
    case unreadablePlist(String)
```

and its description in the `switch`:

```swift
        case .unreadablePlist(let path):
            return "The app's Info.plist at \(path) could not be read."
```

Replace the whole `build(spec:icon:oldWrapper:at:)` method with:

```swift
    /// The instance is a copy-on-write clone of the target app whose identity is patched:
    /// only the Info.plist keys InstancePlist changes, the launcher, and the icon differ from
    /// the original. Running the app's binary from inside this clone is what gives the
    /// instance its own identity to LaunchServices.
    private func build(spec: InstanceSpec, icon: IconChoice, oldWrapper: URL?, at bundleURL: URL) throws {
        let fm = FileManager.default
        try BundleCloner.clone(spec.target.url, to: bundleURL)
        BundleCloner.stripQuarantine(at: bundleURL)
        let contents = bundleURL.appendingPathComponent("Contents")

        let plistURL = contents.appendingPathComponent("Info.plist")
        guard let data = try? Data(contentsOf: plistURL),
              let original = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any]
        else { throw WrapperGeneratorError.unreadablePlist(plistURL.path) }
        let patched = InstancePlist.patch(original, spec: spec)
        try PropertyListSerialization.data(fromPropertyList: patched, format: .xml, options: 0).write(to: plistURL)

        let pkgInfo = contents.appendingPathComponent("PkgInfo")
        if !fm.fileExists(atPath: pkgInfo.path) { try Data("APPL????".utf8).write(to: pkgInfo) }

        // Ad-hoc code cannot use a provisioning profile; leaving it would only confuse validation.
        let profile = contents.appendingPathComponent("embedded.provisionprofile")
        if fm.fileExists(atPath: profile.path) { try fm.removeItem(at: profile) }

        let exec = contents.appendingPathComponent("MacOS").appendingPathComponent(InstancePlist.launcherExecutable)
        if fm.fileExists(atPath: exec.path) { try fm.removeItem(at: exec) }
        try fm.copyItem(at: launcherBinary, to: exec)
        try fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: exec.path)

        // Icon must be written before codesign; the signature seals Resources.
        let resources = contents.appendingPathComponent("Resources")
        try fm.createDirectory(at: resources, withIntermediateDirectories: true)
        try writeIcon(icon, spec: spec, oldWrapper: oldWrapper, to: resources.appendingPathComponent(InstancePlist.iconFile))
    }

    private func writeIcon(_ icon: IconChoice, spec: InstanceSpec, oldWrapper: URL?, to iconDestination: URL) throws {
        let fm = FileManager.default
        switch icon {
        case .original:
            if let sourceIcns = originalIconURL(for: spec.target) {
                try fm.copyItem(at: sourceIcns, to: iconDestination)
            } else {
                // No usable .icns on the target (e.g. Assets.car-only app): fall back to a
                // rendered, unbadged icon.
                let icon = IconBadger.normalizedIcon(NSWorkspace.shared.icon(forFile: spec.target.url.path))
                try IconBadger.writeICNS(icon, to: iconDestination)
            }
        case .badge(let color):
            let icon = IconBadger.normalizedIcon(NSWorkspace.shared.icon(forFile: spec.target.url.path))
            let image = IconBadger.badged(icon, color: color)
            try IconBadger.writeICNS(image, to: iconDestination)
        case .custom(let url):
            let image = try IconBadger.loadImage(at: url)
            try IconBadger.writeICNS(image, to: iconDestination)
        case .keepExisting:
            let oldIcon = oldWrapper?.appendingPathComponent("Contents/Resources").appendingPathComponent(InstancePlist.iconFile)
            if let oldIcon, fm.fileExists(atPath: oldIcon.path) {
                try fm.copyItem(at: oldIcon, to: iconDestination)
            } else {
                // No prior wrapper to copy from (e.g. first-time generation): fall back to badge(.blue).
                let icon = IconBadger.normalizedIcon(NSWorkspace.shared.icon(forFile: spec.target.url.path))
                let image = IconBadger.badged(icon, color: .blue)
                try IconBadger.writeICNS(image, to: iconDestination)
            }
        }
    }
```

Replace the `codesign(_:)` method with:

```swift
    /// Innermost first: helper apps, then every Mach-O in MacOS (the app's binary, the
    /// launcher, anything else the app ships), then the bundle. Chromium requires the browser
    /// and its helpers to share a signing identity, and ad-hoc for all of them satisfies that.
    /// Frameworks are not touched and keep the vendor's signature.
    private func codesign(_ bundle: URL) throws {
        let fm = FileManager.default
        let contents = bundle.appendingPathComponent("Contents")
        let frameworks = contents.appendingPathComponent("Frameworks")
        let helpers = ((try? fm.contentsOfDirectory(at: frameworks, includingPropertiesForKeys: nil)) ?? [])
            .filter { $0.pathExtension == "app" }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
        for helper in helpers { try Codesigner.adhocSign(helper) }
        for executable in BundleCloner.machOExecutables(in: contents.appendingPathComponent("MacOS")) {
            try Codesigner.adhocSign(executable)
        }
        try Codesigner.adhocSign(bundle)
    }
```

Delete the temporary `LegacyWrapperPlist` enum added in Task 1.

- [ ] **Step 5: Run all tests**

Run: `swift test 2>&1 | tail -5`
Expected: all pass, including `EndToEndTests` (the launcher still execs the original at this point, and the fixture script writes args.txt relative to wherever it runs; the E2E test's args.txt path `tmp/args.txt` still holds because the launcher has not changed yet).

- [ ] **Step 6: Commit**

```bash
git add -A Sources Tests
git commit -m "feat(kit): instances are cloned apps with a patched identity, signed ad-hoc"
```

---

### Task 5: Instance format metadata and running detection

**Files:**
- Modify: `Sources/DuplexKit/InstanceStore.swift`
- Create: `Sources/DuplexKit/InstanceRuntime.swift`
- Modify: `Tests/DuplexKitTests/InstanceStoreTests.swift`
- Create: `Tests/DuplexKitTests/InstanceRuntimeTests.swift`

**Interfaces:**
- Produces: `Instance.formatVersion: Int` (1 when the key is missing), `Instance.sourceVersion: String?`, `Instance.bundleID: String` (`com.duplex.<slug>`), `Instance.isLegacy: Bool`.
- Produces: `InstanceRuntime.runningApplications(for: Instance) -> [NSRunningApplication]`, `InstanceRuntime.isRunning(_ instance: Instance) -> Bool`, `InstanceRuntime.quit(_ instance: Instance, timeout: TimeInterval = 8) async -> Bool`.

- [ ] **Step 1: Write failing tests**

Append to `Tests/DuplexKitTests/InstanceStoreTests.swift` inside the class:

```swift
    func testScanReportsCloneFormatAndSourceVersion() throws {
        try generateWrapper(named: "Fake Work", slug: "fake-work")
        let inst = InstanceStore.scan(outputDir: tmp.appendingPathComponent("wrappers"), homePath: tmp.path)[0]
        XCTAssertEqual(inst.formatVersion, 2)
        XCTAssertEqual(inst.sourceVersion, "1.0 (100)")
        XCTAssertEqual(inst.bundleID, "com.duplex.fake-work")
        XCTAssertFalse(inst.isLegacy)
    }

    func testScanReportsLegacyWrapperAsFormatOne() throws {
        let out = tmp.appendingPathComponent("wrappers")
        let contents = out.appendingPathComponent("Old One.app/Contents")
        try FileManager.default.createDirectory(at: contents, withIntermediateDirectories: true)
        let app = try FixtureFactory.makeFakeApp(named: "Fake", bundleID: "com.x.fake", electron: true, in: tmp)
        let spec = InstanceSpec(name: "Old One", slug: "old-one", target: try AppInspector.inspect(app))
        let data = try PropertyListSerialization.data(
            fromPropertyList: FixtureFactory.legacyDuplexPlist(spec: spec), format: .xml, options: 0)
        try data.write(to: contents.appendingPathComponent("Info.plist"))

        let inst = InstanceStore.scan(outputDir: out, homePath: tmp.path)[0]
        XCTAssertEqual(inst.formatVersion, 1)
        XCTAssertNil(inst.sourceVersion)
        XCTAssertTrue(inst.isLegacy)
    }
```

Create `Tests/DuplexKitTests/InstanceRuntimeTests.swift`:

```swift
import XCTest
@testable import DuplexKit

final class InstanceRuntimeTests: XCTestCase {
    var tmp: URL!
    override func setUpWithError() throws { tmp = try FixtureFactory.tempDir(name) }
    override func tearDownWithError() throws { try? FileManager.default.removeItem(at: tmp) }

    func testFreshInstanceIsNotRunning() throws {
        let app = try FixtureFactory.makeFakeApp(named: "Fake", bundleID: "com.x.fake", electron: true, in: tmp)
        let spec = InstanceSpec(name: "Fake Work", slug: "fake-work", target: try AppInspector.inspect(app))
        _ = try WrapperGenerator(launcherBinary: URL(fileURLWithPath: "/bin/ls"))
            .generate(spec: spec, icon: .badge(.blue), outputDir: tmp.appendingPathComponent("wrappers"))
        let inst = InstanceStore.scan(outputDir: tmp.appendingPathComponent("wrappers"), homePath: tmp.path)[0]
        XCTAssertFalse(InstanceRuntime.isRunning(inst))
        XCTAssertEqual(InstanceRuntime.runningApplications(for: inst), [])
    }

    func testQuitOfNothingSucceedsImmediately() async throws {
        let app = try FixtureFactory.makeFakeApp(named: "Fake", bundleID: "com.x.fake", electron: true, in: tmp)
        let spec = InstanceSpec(name: "Fake Work", slug: "fake-work", target: try AppInspector.inspect(app))
        _ = try WrapperGenerator(launcherBinary: URL(fileURLWithPath: "/bin/ls"))
            .generate(spec: spec, icon: .badge(.blue), outputDir: tmp.appendingPathComponent("wrappers"))
        let inst = InstanceStore.scan(outputDir: tmp.appendingPathComponent("wrappers"), homePath: tmp.path)[0]
        let quit = await InstanceRuntime.quit(inst, timeout: 1)
        XCTAssertTrue(quit)
    }
}
```

- [ ] **Step 2: Run to verify failure**

Run: `swift test --filter 'InstanceStoreTests|InstanceRuntimeTests' 2>&1 | tail -5`
Expected: build error (`formatVersion`, `InstanceRuntime` missing).

- [ ] **Step 3: Extend `Instance` and the scan**

In `Sources/DuplexKit/InstanceStore.swift` replace the `Instance` struct with:

```swift
public struct Instance: Equatable, Identifiable {
    public var id: String { slug }
    public let wrapperURL: URL
    public let name: String
    public let slug: String
    public let targetBundleID: String
    public let targetPath: String
    public let urlSchemes: [String]
    public let dataDir: URL
    /// 1 for a 1.1 thin wrapper, 2 for a cloned app with its own identity.
    public let formatVersion: Int
    /// Target version the clone was made from; nil for legacy wrappers.
    public let sourceVersion: String?

    /// The identity the instance's process reports to macOS (clones only; a legacy wrapper's
    /// process reports the target app's identity).
    public var bundleID: String { DuplexPlistKey.bundleIDPrefix + slug }
    public var isLegacy: Bool { formatVersion < DuplexPlistKey.currentFormatVersion }
}
```

In `scan`, replace the `instances.append(Instance(...))` call with:

```swift
            instances.append(Instance(
                wrapperURL: bundle, name: name, slug: slug,
                targetBundleID: targetBundleID, targetPath: targetPath,
                urlSchemes: schemes,
                dataDir: LauncherLogic.dataDir(slug: slug, homePath: homePath),
                formatVersion: plist[DuplexPlistKey.formatVersion] as? Int ?? 1,
                sourceVersion: plist[DuplexPlistKey.sourceVersion] as? String))
```

- [ ] **Step 4: Create `InstanceRuntime`**

Create `Sources/DuplexKit/InstanceRuntime.swift`:

```swift
import AppKit

/// Live-process questions about an instance. Only meaningful for clones (format 2), whose
/// processes carry the instance's own bundle identifier.
public enum InstanceRuntime {
    public static func runningApplications(for instance: Instance) -> [NSRunningApplication] {
        NSRunningApplication.runningApplications(withBundleIdentifier: instance.bundleID)
    }

    public static func isRunning(_ instance: Instance) -> Bool {
        !runningApplications(for: instance).isEmpty
    }

    /// Asks every process of the instance to quit and waits up to `timeout` seconds for them
    /// to exit. Returns true when none is left running.
    public static func quit(_ instance: Instance, timeout: TimeInterval = 8) async -> Bool {
        let apps = runningApplications(for: instance)
        if apps.isEmpty { return true }
        for app in apps { app.terminate() }
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if apps.allSatisfy(\.isTerminated) { return true }
            try? await Task.sleep(nanoseconds: 200_000_000)
        }
        return apps.allSatisfy(\.isTerminated)
    }
}
```

- [ ] **Step 5: Run tests**

Run: `swift test 2>&1 | tail -5`
Expected: all pass.

- [ ] **Step 6: Commit**

```bash
git add -A Sources Tests
git commit -m "feat(kit): instances expose format and source version; InstanceRuntime detects running clones"
```

---

### Task 6: Launcher runs the clone and follows the original's updates

**Files:**
- Modify: `Sources/duplex-launcher/main.swift`
- Modify: `Tests/DuplexKitTests/EndToEndTests.swift`

**Interfaces:**
- Consumes: `LauncherLogic.config/needsResync/execArguments/dataDir/resolveTarget` (Task 2), `InstancePlist.sourceVersion(ofBundleAt:)` (Task 1), `WrapperGenerator.generate` (Task 4), `AppInspector.inspect`, `InstanceSpec`.
- Behaviour: the launcher execs `<own bundle>/Contents/MacOS/<DuplexTargetExecutable>`; when the original's version differs from `DuplexSourceVersion`, it regenerates its own bundle first under an exclusive `flock` on `<App Support>/Duplex/<slug>/resync.lock`; on regeneration failure it runs the existing clone.

- [ ] **Step 1: Update the end-to-end tests**

Replace the body of `Tests/DuplexKitTests/EndToEndTests.swift` from `func testWrapperLaunchesTargetWithUserDataDir` to the end of the class with:

```swift
    private func runLauncher(in wrapper: URL, home: URL) throws -> Int32 {
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
        let p = Process()
        p.executableURL = wrapper.appendingPathComponent("Contents/MacOS/duplex-launcher")
        var env = ProcessInfo.processInfo.environment
        env["HOME"] = home.path
        p.environment = env
        try p.run()
        p.waitUntilExit()
        return p.terminationStatus
    }

    private func plist(of bundle: URL) throws -> [String: Any] {
        let data = try Data(contentsOf: bundle.appendingPathComponent("Contents/Info.plist"))
        return try PropertyListSerialization.propertyList(from: data, format: nil) as! [String: Any]
    }

    /// The fixture script writes "$0 $@" next to the bundle it ran from: for a clone, that is
    /// the wrappers directory.
    private func recordedArgs() throws -> String {
        let argsFile = tmp.appendingPathComponent("wrappers/args.txt")
        XCTAssertTrue(FileManager.default.fileExists(atPath: argsFile.path), "the clone's binary should have run")
        return try String(contentsOf: argsFile, encoding: .utf8)
    }

    private func makeWrapper() throws -> (app: URL, wrapper: URL) {
        let fakeApp = try FixtureFactory.makeFakeApp(
            named: "FakeTron", bundleID: "com.duplex-tests.faketron", electron: true, in: tmp)
        let spec = InstanceSpec(name: "FakeTron Work", slug: "faketron-work",
                                target: try AppInspector.inspect(fakeApp))
        let gen = WrapperGenerator(launcherBinary: try builtLauncherURL())
        let wrapper = try gen.generate(spec: spec, icon: .badge(.green),
                                       outputDir: tmp.appendingPathComponent("wrappers"))
        return (fakeApp, wrapper)
    }

    func testLauncherRunsTheClonesOwnBinaryWithUserDataDir() throws {
        let (_, wrapper) = try makeWrapper()
        let fakeHome = tmp.appendingPathComponent("home")
        XCTAssertEqual(try runLauncher(in: wrapper, home: fakeHome), 0)

        let args = try recordedArgs()
        XCTAssertTrue(args.hasPrefix(wrapper.appendingPathComponent("Contents/MacOS/FakeTron").path),
                      "must run the binary inside the clone, not the original; got: \(args)")
        let expectedDataDir = fakeHome.path + "/Library/Application Support/Duplex/faketron-work/data"
        XCTAssertTrue(args.contains("--user-data-dir=\(expectedDataDir)"), "got: \(args)")
        XCTAssertTrue(args.contains("--use-mock-keychain"), "got: \(args)")
        XCTAssertTrue(FileManager.default.fileExists(atPath: expectedDataDir), "launcher must create the data dir")
    }

    func testLauncherRegeneratesCloneWhenTargetVersionChanges() throws {
        let (fakeApp, wrapper) = try makeWrapper()
        XCTAssertEqual(try plist(of: wrapper)[DuplexPlistKey.sourceVersion] as? String, "1.0 (100)")

        try FixtureFactory.setVersion(of: fakeApp, short: "2.0", build: "200")
        XCTAssertEqual(try runLauncher(in: wrapper, home: tmp.appendingPathComponent("home")), 0)

        XCTAssertEqual(try plist(of: wrapper)[DuplexPlistKey.sourceVersion] as? String, "2.0 (200)",
                       "clone should have been rebuilt from the updated original")
        XCTAssertEqual(try plist(of: wrapper)["CFBundleShortVersionString"] as? String, "2.0")
        XCTAssertTrue(try recordedArgs().contains("--user-data-dir="))
        let leftovers = try FileManager.default.contentsOfDirectory(atPath: tmp.appendingPathComponent("wrappers").path)
            .filter { $0.hasPrefix(".duplex-staging") }
        XCTAssertEqual(leftovers, [])
        XCTAssertTrue(FileManager.default.fileExists(
            atPath: tmp.appendingPathComponent("home/Library/Application Support/Duplex/faketron-work/resync.lock").path),
            "lock file is created under the instance's App Support folder")
    }

    func testLauncherRunsExistingCloneWhenRegenerationFails() throws {
        let (fakeApp, wrapper) = try makeWrapper()
        try FixtureFactory.setVersion(of: fakeApp, short: "2.0", build: "200")
        // Without the framework the original no longer passes AppInspector, so regeneration
        // fails; the launcher must still run the stale clone.
        try FileManager.default.removeItem(at: fakeApp.appendingPathComponent("Contents/Frameworks/Electron Framework.framework"))

        XCTAssertEqual(try runLauncher(in: wrapper, home: tmp.appendingPathComponent("home")), 0)
        XCTAssertEqual(try plist(of: wrapper)[DuplexPlistKey.sourceVersion] as? String, "1.0 (100)", "unchanged")
        XCTAssertTrue(try recordedArgs().contains("--use-mock-keychain"))
    }
}
```

- [ ] **Step 2: Run to verify failure**

Run: `swift build && swift test --filter EndToEndTests 2>&1 | grep -E "error|failed|passed" | head`
Expected: `testLauncherRunsTheClonesOwnBinaryWithUserDataDir` fails on the `hasPrefix` assertion (the launcher still execs the original); the regeneration test fails on `sourceVersion`.

- [ ] **Step 3: Rewrite the launcher**

Replace `Sources/duplex-launcher/main.swift` with:

```swift
import AppKit
import DuplexKit

func fail(_ message: String) -> Never {
    CFUserNotificationDisplayAlert(
        0, kCFUserNotificationCautionAlertLevel,
        nil, nil, nil,
        "Duplex" as CFString, message as CFString,
        nil, nil, nil, nil)
    exit(1)
}

func log(_ message: String) {
    FileHandle.standardError.write(Data(("duplex-launcher: " + message + "\n").utf8))
}

/// Reads this bundle's configuration from disk rather than Bundle.main's cache, so a bundle
/// that was just regenerated is seen as it is now.
func readConfig(bundle: URL) -> LauncherConfig? {
    let plistURL = bundle.appendingPathComponent("Contents/Info.plist")
    guard let data = try? Data(contentsOf: plistURL),
          let info = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any]
    else { return nil }
    return LauncherLogic.config(from: info)
}

func resolveTarget(_ config: LauncherConfig) -> URL? {
    LauncherLogic.resolveTarget(
        lsResolved: NSWorkspace.shared.urlForApplication(withBundleIdentifier: config.targetBundleID),
        fallbackPath: config.targetPath,
        fileExists: { FileManager.default.fileExists(atPath: $0) })
}

var bundleURL = Bundle.main.bundleURL
guard var config = readConfig(bundle: bundleURL) else {
    fail("This instance is missing its Duplex configuration. Recreate it in Duplex.")
}
guard let appURL = resolveTarget(config) else {
    fail("The original app (\(config.targetBundleID)) could not be found. Was it uninstalled?")
}

// $HOME env var by design: launched normally it's the real home, and tests can redirect it.
let home = ProcessInfo.processInfo.environment["HOME"] ?? NSHomeDirectory()
let dataDir = LauncherLogic.dataDir(slug: config.slug, homePath: home)
do {
    try FileManager.default.createDirectory(at: dataDir, withIntermediateDirectories: true)
} catch {
    fail("Could not create the instance data folder at \(dataDir.path).")
}

// Drift: when the original app has updated since this clone was made, rebuild the clone in
// place before running it. Serialized per instance so two quick launches cannot race.
let installedVersion = InstancePlist.sourceVersion(ofBundleAt: appURL)
if LauncherLogic.needsResync(recorded: config.sourceVersion, installed: installedVersion) {
    let lockPath = dataDir.deletingLastPathComponent().appendingPathComponent("resync.lock").path
    let fd = open(lockPath, O_CREAT | O_RDWR, 0o644)
    if fd >= 0 { flock(fd, LOCK_EX) }
    // Another launcher may have finished the job while we waited for the lock.
    if let fresh = readConfig(bundle: bundleURL),
       LauncherLogic.needsResync(recorded: fresh.sourceVersion, installed: installedVersion) {
        do {
            let target = try AppInspector.inspect(appURL)
            let spec = InstanceSpec(name: fresh.name, slug: fresh.slug, target: target)
            guard let launcher = Bundle.main.executableURL else { throw CocoaError(.fileNoSuchFile) }
            // Regenerating from inside the bundle is safe: the running launcher's file stays
            // valid after the old bundle is removed, and the new one lands at the same path.
            bundleURL = try WrapperGenerator(launcherBinary: launcher)
                .generate(spec: spec, icon: .keepExisting, outputDir: bundleURL.deletingLastPathComponent())
        } catch {
            log("could not refresh this instance from \(appURL.path): \(error.localizedDescription). Running the existing copy.")
        }
    }
    if fd >= 0 { flock(fd, LOCK_UN); close(fd) }
    if let fresh = readConfig(bundle: bundleURL) { config = fresh }
}

// The clone's own copy of the app binary. Running it from inside this bundle is what gives
// the instance its own identity to macOS.
let executableName = config.targetExecutable
    ?? (try? AppInspector.inspect(appURL))?.executable
    ?? appURL.deletingPathExtension().lastPathComponent
let execURL = bundleURL.appendingPathComponent("Contents/MacOS").appendingPathComponent(executableName)
guard FileManager.default.isExecutableFile(atPath: execURL.path) else {
    fail("This instance is incomplete (\(executableName) is missing). Open Duplex and edit the instance to rebuild it.")
}

let args = LauncherLogic.execArguments(targetExecutable: execURL.path, dataDir: dataDir)
var cargs: [UnsafeMutablePointer<CChar>?] = args.map { strdup($0) }
cargs.append(nil)
execv(args[0], cargs)
// execv only returns on failure.
fail("Failed to launch \(config.name) (errno \(errno)).")
```

- [ ] **Step 4: Run the whole suite**

Run: `swift build && swift test 2>&1 | tail -5`
Expected: all pass, including the three end-to-end tests.

- [ ] **Step 5: Commit**

```bash
git add -A Sources Tests
git commit -m "feat(launcher): run the clone's own binary and regenerate when the original updates"
```

---

### Task 7: App layer: async creation, migration, running guard

**Files:**
- Modify: `Sources/Duplex/AppState.swift`
- Modify: `Sources/Duplex/InstanceListView.swift`
- Modify: `Sources/Duplex/InstanceEditorSheet.swift` (the `submit()` function and the button that calls it)

**Interfaces:**
- Consumes: `Instance.isLegacy`, `InstanceRuntime` (Task 5), `WrapperGenerator` (Task 4), `AppInspector`.
- Produces: `AppState.isBusy: Bool`, `AppState.migrationNotice: String?`, `AppState.blockedAction: AppState.BlockedAction?`, `AppState.create(name:appURL:icon:existingSlug:) async -> Bool`, `AppState.guardNotRunning(_ action: BlockedAction) -> Bool`, `AppState.quitAndContinue(_ action: BlockedAction) async -> Bool`. `launchOriginal` is removed.

- [ ] **Step 1: Rewrite `AppState`**

Replace `Sources/Duplex/AppState.swift` with:

```swift
import AppKit
import SwiftUI
import DuplexKit

@MainActor
final class AppState: ObservableObject {
    @Published var instances: [Instance] = []
    @Published var dataSizes: [String: Int64] = [:]
    @Published var errorMessage: String?
    @Published var showLicenseSheet = false
    /// True while a clone is being generated or an instance is being quit; the UI disables
    /// creation and editing and shows a progress indicator.
    @Published var isBusy = false
    /// One-time notice after 1.1 wrappers were upgraded to clones.
    @Published var migrationNotice: String?
    /// An edit or delete the user asked for while the instance was running.
    @Published var blockedAction: BlockedAction?

    enum BlockedAction: Identifiable {
        case edit(Instance)
        case delete(Instance)
        var instance: Instance {
            switch self {
            case .edit(let i), .delete(let i): return i
            }
        }
        var id: String {
            switch self {
            case .edit(let i): return "edit-\(i.slug)"
            case .delete(let i): return "delete-\(i.slug)"
            }
        }
    }

    let license: LicenseManager

    init(license: LicenseManager? = nil) {
        self.license = license ?? LicenseManager()
    }

    var canCreateNewInstance: Bool {
        LicenseGate.canCreate(existingCount: instances.count, isRegeneration: false,
                              licensed: license.isLicensed)
    }

    let outputDir = WrapperGenerator.defaultOutputDir()
    private var homePath: String { ProcessInfo.processInfo.environment["HOME"] ?? NSHomeDirectory() }
    private var isMigrating = false
    /// Slugs whose migration already failed this session; not retried on every refresh.
    private var migrationFailed: Set<String> = []

    func refresh() {
        instances = InstanceStore.scan(outputDir: outputDir, homePath: homePath)
        var sizes: [String: Int64] = [:]
        for instance in instances {
            sizes[instance.slug] = InstanceStore.dataSize(of: instance)
        }
        dataSizes = sizes
        if instances.contains(where: { $0.isLegacy && !migrationFailed.contains($0.slug) }) {
            Task { await migrateLegacyInstances() }
        }
    }

    /// The launcher binary: inside Duplex.app it's bundled in Resources;
    /// during `swift run` it sits next to the Duplex executable in .build/.
    static func launcherURL() -> URL? {
        if let bundled = Bundle.main.url(forResource: "duplex-launcher", withExtension: nil) {
            return bundled
        }
        let sibling = URL(fileURLWithPath: CommandLine.arguments[0])
            .deletingLastPathComponent()
            .appendingPathComponent("duplex-launcher")
        return FileManager.default.isExecutableFile(atPath: sibling.path) ? sibling : nil
    }

    private func targetURL(for instance: Instance) -> URL? {
        LauncherLogic.resolveTarget(
            lsResolved: NSWorkspace.shared.urlForApplication(withBundleIdentifier: instance.targetBundleID),
            fallbackPath: instance.targetPath,
            fileExists: { FileManager.default.fileExists(atPath: $0) })
    }

    /// Generation clones and signs an app bundle: about two seconds, longer on the copy
    /// fallback, so it runs off the main actor.
    private func generate(spec: InstanceSpec, icon: IconChoice, launcher: URL) async throws {
        let generator = WrapperGenerator(launcherBinary: launcher)
        let outputDir = self.outputDir
        try await Task.detached(priority: .userInitiated) {
            _ = try generator.generate(spec: spec, icon: icon, outputDir: outputDir)
        }.value
    }

    /// Returns true on success. On failure `errorMessage` is set.
    func create(name: String, appURL: URL, icon: IconChoice, existingSlug: String? = nil) async -> Bool {
        guard LicenseGate.canCreate(existingCount: instances.count,
                                    isRegeneration: existingSlug != nil,
                                    licensed: license.isLicensed) else {
            showLicenseSheet = true
            return false
        }
        if let existingSlug, let existing = instances.first(where: { $0.slug == existingSlug }),
           InstanceRuntime.isRunning(existing) {
            errorMessage = "\(existing.name) is running. Quit it before changing it."
            return false
        }
        isBusy = true
        defer { isBusy = false }
        do {
            guard let launcher = Self.launcherURL() else {
                throw NSError(domain: "Duplex", code: 1, userInfo: [
                    NSLocalizedDescriptionKey: "duplex-launcher binary not found. Build it with `swift build` or run from Duplex.app."])
            }
            let target = try AppInspector.inspect(appURL)
            let slug = existingSlug ?? SlugGenerator.slug(from: name, existing: Set(instances.map(\.slug)))
            let spec = InstanceSpec(name: name, slug: slug, target: target)
            try await generate(spec: spec, icon: icon, launcher: launcher)
            refresh()
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    /// Upgrades 1.1 thin wrappers to clones. Regeneration is never license-gated. A legacy
    /// wrapper's process is the original app's binary, so replacing the wrapper while it runs
    /// is harmless.
    func migrateLegacyInstances() async {
        guard !isMigrating, let launcher = Self.launcherURL() else { return }
        isMigrating = true
        isBusy = true
        defer { isMigrating = false; isBusy = false }

        let legacy = instances.filter { $0.isLegacy && !migrationFailed.contains($0.slug) }
        var migrated = 0
        var failures: [String] = []
        for instance in legacy {
            do {
                guard let appURL = targetURL(for: instance) else {
                    throw NSError(domain: "Duplex", code: 2, userInfo: [
                        NSLocalizedDescriptionKey: "the original app (\(instance.targetBundleID)) could not be found"])
                }
                let target = try AppInspector.inspect(appURL)
                let spec = InstanceSpec(name: instance.name, slug: instance.slug, target: target)
                try await generate(spec: spec, icon: .keepExisting, launcher: launcher)
                migrated += 1
            } catch {
                migrationFailed.insert(instance.slug)
                failures.append("\(instance.name): \(error.localizedDescription)")
            }
        }
        refresh()
        if migrated > 0 {
            let noun = migrated == 1 ? "instance" : "instances"
            migrationNotice = "Duplex updated \(migrated) \(noun) to the new format so each has its own identity. Because session storage changed, sign in again in each instance."
        }
        if !failures.isEmpty {
            errorMessage = "Some instances could not be updated:\n" + failures.joined(separator: "\n")
        }
    }

    func launch(_ instance: Instance) {
        NSWorkspace.shared.openApplication(
            at: instance.wrapperURL, configuration: NSWorkspace.OpenConfiguration()) { _, error in
            if let error {
                Task { @MainActor in self.errorMessage = error.localizedDescription }
            }
        }
    }

    /// Editing or deleting a running clone would pull the bundle out from under its live
    /// process. Returns true when the action may proceed now; otherwise records it so the UI
    /// can offer to quit the instance first.
    func guardNotRunning(_ action: BlockedAction) -> Bool {
        if InstanceRuntime.isRunning(action.instance) {
            blockedAction = action
            return false
        }
        return true
    }

    func quitAndContinue(_ action: BlockedAction) async -> Bool {
        isBusy = true
        defer { isBusy = false }
        let quit = await InstanceRuntime.quit(action.instance)
        if !quit {
            errorMessage = "\(action.instance.name) did not quit. Quit it manually and try again."
        }
        return quit
    }

    func revealData(_ instance: Instance) {
        try? FileManager.default.createDirectory(at: instance.dataDir, withIntermediateDirectories: true)
        NSWorkspace.shared.activateFileViewerSelecting([instance.dataDir])
    }

    func routeLinks(to instance: Instance) {
        for scheme in instance.urlSchemes {
            URLSchemeRouter.setHandler(appURL: instance.wrapperURL, forScheme: scheme) { error in
                if let error {
                    Task { @MainActor in self.errorMessage = error.localizedDescription }
                }
            }
        }
    }

    func routeLinksToOriginal(_ instance: Instance) {
        guard let originalURL = NSWorkspace.shared.urlForApplication(
            withBundleIdentifier: instance.targetBundleID) else { return }
        for scheme in instance.urlSchemes {
            URLSchemeRouter.setHandler(appURL: originalURL, forScheme: scheme) { error in
                if let error {
                    Task { @MainActor in self.errorMessage = error.localizedDescription }
                }
            }
        }
    }

    func delete(_ instance: Instance, includingData: Bool) {
        do {
            try InstanceStore.delete(instance, includingData: includingData)
            refresh()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
```

- [ ] **Step 2: Update the list view**

In `Sources/Duplex/InstanceListView.swift`:

(a) In `menuItems(_:)`, replace the whole function with:

```swift
    @ViewBuilder
    private func menuItems(_ instance: Instance) -> some View {
        Button("Edit\u{2026}") {
            if state.guardNotRunning(.edit(instance)) { editorTarget = .edit(instance) }
        }
        Button("Reveal Data Folder") { state.revealData(instance) }
        if !instance.urlSchemes.isEmpty {
            Button("Route Links Here") { state.routeLinks(to: instance) }
            Button("Route Links to Original App") { state.routeLinksToOriginal(instance) }
        }
        Divider()
        Button("Delete\u{2026}", role: .destructive) {
            if state.guardNotRunning(.delete(instance)) { deleteCandidate = instance }
        }
    }
```

(b) After the existing `.alert("Duplex", ...)` modifier in `body`, add two more alerts:

```swift
        .alert("\(state.blockedAction?.instance.name ?? "This instance") is running",
               isPresented: Binding(get: { state.blockedAction != nil },
                                    set: { if !$0 { state.blockedAction = nil } })) {
            Button("Quit and Continue") {
                guard let action = state.blockedAction else { return }
                state.blockedAction = nil
                Task {
                    guard await state.quitAndContinue(action) else { return }
                    switch action {
                    case .edit(let i): editorTarget = .edit(i)
                    case .delete(let i): deleteCandidate = i
                    }
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Changing or deleting an instance while it runs would pull the app out from under it. Duplex can quit it first.")
        }
        .alert("Instances updated", isPresented: Binding(
            get: { state.migrationNotice != nil },
            set: { if !$0 { state.migrationNotice = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(state.migrationNotice ?? "")
        }
```

(c) Disable creation while busy: in `newInstanceToolbarButton`, add `.disabled(state.isBusy)` after `.help(...)`. In `row(_:)`, add `.disabled(state.isBusy)` to the Launch button after `.fixedSize()`.

(d) Show progress in the status bar: in `statusBar`, immediately after `Spacer()`, add:

```swift
                if state.isBusy {
                    ProgressView().controlSize(.small)
                    Text("Working\u{2026}").font(.caption).foregroundStyle(.secondary)
                }
```

- [ ] **Step 3: Make the editor sheet submit asynchronously**

In `Sources/Duplex/InstanceEditorSheet.swift`, replace `submit()` with:

```swift
    private func submit() {
        guard let appURL else { return }
        let icon: IconChoice
        switch iconMode {
        case .keep: icon = .keepExisting
        case .original: icon = .original
        case .badge: icon = .badge(badgeColor)
        case .custom: icon = .custom(customIconURL!)
        }
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        let slug = existing?.slug
        Task {
            let ok = await state.create(name: trimmed, appURL: appURL, icon: icon, existingSlug: slug)
            if ok {
                dismiss()
            } else {
                // The error alert lives on the parent view, under this sheet, so it would never
                // be seen here. Surface the failure inline and keep the sheet open.
                validationError = state.errorMessage
                state.errorMessage = nil
            }
        }
    }
```

Then find the button whose action calls `submit()` (search the file for `submit()`), and add `.disabled(state.isBusy)` to it in addition to any existing `.disabled(...)` condition. Add `if state.isBusy { ProgressView().controlSize(.small) }` next to that button so the user sees the sheet is working.

- [ ] **Step 4: Build and run the app**

Run: `swift build 2>&1 | grep -E "error|warning: unused" ; swift test 2>&1 | tail -3`
Expected: clean build, all tests pass.

Run: `./scripts/build-app.sh && open dist/Duplex.app`
Check by hand: the window opens, the list shows existing instances, no "Launch Original App" item in the row menu, creating a new instance shows "Working…" in the status bar and finishes in a few seconds. Quit the app afterwards.

- [ ] **Step 5: Commit**

```bash
git add -A Sources
git commit -m "feat(app): async clone creation, legacy migration, running-instance guard"
```

---

### Task 8: Version bump and documentation

**Files:**
- Modify: `scripts/build-app.sh:26-27`
- Modify: `README.md`
- Modify (site repo `/Users/nimit/Documents/Projects/aetrixfoundry`): `duplex/index.html:171-175`, `terms/index.html:43`

**Constraints:** no em dashes in any of these files. Verify with `grep -c ", " README.md` (must print 0) and the same on the two site files.

- [ ] **Step 1: Bump the version**

In `scripts/build-app.sh` change

```
    <key>CFBundleShortVersionString</key><string>1.1.3</string>
    <key>CFBundleVersion</key><string>5</string>
```

to

```
    <key>CFBundleShortVersionString</key><string>1.2.0</string>
    <key>CFBundleVersion</key><string>6</string>
```

- [ ] **Step 2: Rewrite the README sections that describe the mechanism**

Replace the opening paragraph (lines 3-11) with:

```markdown
Duplex is a small macOS utility for running multiple, independent instances of
an Electron-based app side by side, such as two Claude Desktop windows
logged into two different accounts at the same time. macOS normally refuses to
launch a second copy of the same app, and Electron apps additionally lock
their profile directory, so this doesn't work out of the box. Duplex works
around both by creating a lightweight clone of the app for each instance: a
copy-on-write copy of the app bundle that shares its disk blocks with the
original, carries its own identity so macOS treats it as a separate app, and
starts the app with a private data directory. Every instance gets its own
cookies, local storage, and login session, and the original app is never
modified.
```

Replace the "How it works" section (lines 25-36) with:

```markdown
## How it works

Each instance Duplex creates is a clone of the target app, not a shortcut to it.

1. The app bundle is cloned with APFS copy-on-write, so the clone shares disk
   blocks with the original and takes about two seconds to make. Finder reports
   it at the app's full size, but it costs almost no space.
2. The clone's Info.plist gets a new bundle identifier (`com.duplex.<slug>`),
   your instance name, and your chosen icon. Everything else stays as the app
   shipped it.
3. The app's own binary and helper apps inside the clone are re-signed with an
   ad-hoc signature so macOS accepts the changed identity. The large frameworks
   keep the vendor's signature untouched.
4. A small launcher inside the clone starts the app's binary with
   `--user-data-dir=~/Library/Application Support/Duplex/<slug>/data`, which
   Electron/Chromium honors by keeping the whole profile, including the
   single-instance lock, inside that folder.

Because the running process lives inside the clone, macOS sees a separate
application: the original launches from the Dock while instances run, and login
callbacks such as `claude://` are delivered to the instance you routed them to.

Instances follow the original app's updates. On every launch the launcher
compares the installed app's version with the one the clone was made from and,
when they differ, rebuilds the clone before starting it. The app's own updater
inside an instance cannot install anything (it refuses to replace an ad-hoc
signed bundle), which is what keeps the clone consistent.

Instances cannot use the original app's keychain entry, because macOS ties it
to the vendor's signing identity. They therefore run with Chromium's
`--use-mock-keychain` switch: the saved session is encrypted with a fixed key
and protected by your macOS user account permissions, the same model Chromium
uses on Linux without a keyring. The original app is unaffected.
```

Replace Usage steps 2 and 3 (lines 66-76) with:

```markdown
2. **Launch it**: click Launch on the instance's row, or open it from
   `/Applications` like any app. The clone starts with its own private data
   directory, so it opens to a fresh, logged-out state the first time. The
   original app keeps launching normally from the Dock while instances run.
3. **Log in**: before logging in, use the instance's "Route Links Here" action
   so that OAuth/deep-link callbacks (e.g. `claude://...`) come back to this
   instance instead of the original app or another instance. Complete the
   login in the instance's window, then hand the link routing back to the
   original app (or whichever instance you'll use next) so future logins go
   to the right place.
```

In the Known Quirks table, delete the row that begins `| Original app launched from Dock/Finder while an instance is running |` and add these rows before the `| Delete instance |` row:

```markdown
| Instance size in Finder | Finder and `du` report the app's full size, but the clone is copy-on-write and shares disk blocks with the original until the original updates; the next instance launch rebuilds the clone and the sharing resumes |
| Permissions asked again after the original app updates | Rebuilding a clone re-signs it, and macOS ties permissions such as Desktop or microphone access to the signature, so an instance may ask again |
| Editing or deleting a running instance | Duplex asks to quit the instance first, because the change replaces the bundle the app is running from |
| Upgrading from Duplex 1.1 | Existing instances are rebuilt as clones on first launch (one-time notice). Profiles are kept, but because session storage changed you sign in again once per instance |
| Update prompts inside an instance | The app's own updater cannot install into a clone. Update the original app; the instance follows on its next launch |
| Mac App Store builds of apps | Not supported: their receipt validation rejects a changed bundle identifier |
```

- [ ] **Step 3: Verify no em dashes and commit**

Run: `grep -c ", " README.md scripts/build-app.sh`
Expected: `0` for both.

```bash
git add README.md scripts/build-app.sh
git commit -m "docs: describe cloned instances; bump to 1.2.0"
```

- [ ] **Step 4: Update the site copy (separate repo)**

In `/Users/nimit/Documents/Projects/aetrixfoundry/duplex/index.html` replace the card

```html
    <div class="card">
      <h3>The original stays untouched</h3>
      <p>Wrappers launch the app's own binary with an isolated profile. No
      patching, no re-signing, updates keep flowing.</p>
    </div>
```

with

```html
    <div class="card">
      <h3>The original stays untouched</h3>
      <p>Each instance is a copy-on-write clone of the app with its own
      identity. The original is never modified, keeps updating itself, and
      instances follow its updates.</p>
    </div>
```

and the card

```html
    <div class="card">
      <h3>Logins that actually work</h3>
      <p>OAuth callbacks route to one app on macOS. Duplex's link routing sends
      them to the instance you are signing in to.</p>
    </div>
```

with

```html
    <div class="card">
      <h3>Logins that actually work</h3>
      <p>macOS sees every instance as a separate app, so the original opens
      from the Dock while instances run, and Duplex's link routing sends OAuth
      callbacks to the instance you are signing in to.</p>
    </div>
```

In `/Users/nimit/Documents/Projects/aetrixfoundry/terms/index.html` replace the sentence
`Duplex does not include, redistribute, or modify those third party apps.`
with
`Duplex does not include or redistribute those third party apps, and never modifies your original installation.`

Run: `cd /Users/nimit/Documents/Projects/aetrixfoundry && grep -c ", " duplex/index.html terms/index.html`
Expected: `0` for both.

```bash
cd /Users/nimit/Documents/Projects/aetrixfoundry
git add duplex/index.html terms/index.html
git commit -m "duplex: describe cloned instances with their own identity"
```

Do not push the site; the release task pushes both repos together.

---

### Task 9: Release 1.2.0 (main session, with the user)

This task is run by the coordinating session, not a subagent, because notarization can take a while and the manual checks need the user at the GUI.

- [ ] **Step 1: Build, sign, notarize**

```bash
cd "/Users/nimit/Documents/Projects/App Duplicator"
swift test 2>&1 | tail -3
./scripts/build-app.sh
./scripts/release.sh
```

If `notarytool --wait` dies mid-poll: `./scripts/resume-notary.sh <submission-id>`.

- [ ] **Step 2: Local install and the user's manual checks**

Install the freshly built `dist/Duplex.app` over `/Applications/Duplex.app` (quit the running Duplex first), then the user checks:

1. Launch Duplex: the one-time "Instances updated" notice appears; existing instances launch and show the sign-in screen.
2. With an instance running, the original Claude opens from the Dock as a separate app.
3. In an instance: Route Links Here, then Sign in with Google; the callback lands in that instance and the original stays on its own account.
4. Editing a running instance shows the "is running" alert with Quit and Continue.

Fix anything found before publishing.

- [ ] **Step 3: Publish**

```bash
gh release create v1.2.0 dist/Duplex-1.2.0.zip --title "Duplex 1.2.0" --repo bnimit/duplex --notes "Instances now have their own identity: the original app launches alongside them and sign-in callbacks reach the right instance. Existing instances are upgraded automatically; sign in again once per instance."
```

Paste the sha256 printed by `release.sh` into `packaging/duplex.rb` (version `1.2.0`) and copy it to `/Users/nimit/Documents/Projects/homebrew-tap/Casks/duplex.rb`. Commit and push both repos plus the site repo:

```bash
git add packaging/duplex.rb && git commit -m "build: cask 1.2.0" && git push
cd /Users/nimit/Documents/Projects/homebrew-tap && git add Casks/duplex.rb && git commit -m "duplex 1.2.0" && git push
cd /Users/nimit/Documents/Projects/aetrixfoundry && git push
```

- [ ] **Step 4: Verify the brew path**

```bash
brew update && brew upgrade --cask duplex && plutil -extract CFBundleShortVersionString raw /Applications/Duplex.app/Contents/Info.plist
```

Expected: `1.2.0`.
