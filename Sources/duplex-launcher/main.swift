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

/// A two-button caution alert, rendered like `fail`'s. Returns true when the user picks the
/// default (left-most) button. `fallback` is used when the alert cannot be shown at all, so a
/// launch without a window server still decides rather than hanging.
func confirm(_ message: String, default defaultTitle: String, other otherTitle: String,
             fallback: Bool) -> Bool {
    var response: CFOptionFlags = 0
    let status = CFUserNotificationDisplayAlert(
        0, kCFUserNotificationCautionAlertLevel,
        nil, nil, nil,
        "Duplex" as CFString, message as CFString,
        defaultTitle as CFString, otherTitle as CFString, nil,
        &response)
    guard status == 0 else { return fallback }
    return response == CFOptionFlags(kCFUserNotificationDefaultResponse)
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

/// The clone's own copy of the app binary, using the same fallback chain as WrapperGenerator:
/// the recorded executable name, then AppInspector on the original, then the app's base name.
func cloneExecutableURL(config: LauncherConfig, bundle: URL, appURL: URL) -> URL {
    let executableName = config.targetExecutable
        ?? (try? AppInspector.inspect(appURL))?.executable
        ?? appURL.deletingPathExtension().lastPathComponent
    return bundle.appendingPathComponent("Contents/MacOS").appendingPathComponent(executableName)
}

let installedVersion = InstancePlist.sourceVersion(ofBundleAt: appURL)

func versionChange(_ config: LauncherConfig) -> LauncherLogic.VersionChange {
    LauncherLogic.versionChange(recorded: config.sourceVersion, installed: installedVersion)
}

/// True when an interrupted resync left the clone without its own copy of the app binary.
func cloneBinaryMissing(_ config: LauncherConfig, _ bundle: URL) -> Bool {
    !FileManager.default.isExecutableFile(
        atPath: cloneExecutableURL(config: config, bundle: bundle, appURL: appURL).path)
}

/// True when the original has updated since this clone was made, or the clone is incomplete.
/// A downgrade is deliberately not a rebuild: see the check below.
func cloneNeedsRebuild(_ config: LauncherConfig, _ bundle: URL) -> Bool {
    versionChange(config).rebuilds || cloneBinaryMissing(config, bundle)
}

// The original app has been rolled back. Resyncing would replace this clone's binary with the
// older one while keeping a profile the newer binary may already have migrated forward, which
// Chromium can refuse to open — so say so instead of guessing. The clone still holds its own
// copy of the newer app, so running it unchanged is the safe option and the default. A clone
// that has lost its binary cannot be run at all, so that case still rebuilds.
if versionChange(config) == .downgrade {
    let recorded = config.sourceVersion ?? "an unknown version"
    let installed = installedVersion ?? "an unknown version"
    if cloneBinaryMissing(config, bundleURL) {
        log("the original app went back from \(recorded) to \(installed), but this instance has lost its copy of the app, so it must be rebuilt from the older version.")
    } else {
        let message = """
            \(config.name) was made from version \(recorded) of the original app, but the copy \
            installed now is the older \(installed).

            This instance's data was last used by the newer version, which may already have \
            migrated it to a format the older app cannot read. Duplex has therefore left the \
            instance alone rather than rebuilding it backwards: it still runs the newer app it \
            was made from, and its data is untouched.

            Open it anyway, or quit and either reinstall the newer app, or delete this \
            instance's data in Duplex and sign in again on the older one.
            """
        guard confirm(message, default: "Open Anyway", other: "Quit", fallback: true) else {
            exit(0)
        }
    }
}

// Rebuild the clone in place before running it when the original has updated or the clone is
// incomplete. Serialized per instance so two quick launches cannot race.
if cloneNeedsRebuild(config, bundleURL) {
    let lockPath = dataDir.deletingLastPathComponent().appendingPathComponent("resync.lock").path
    let fd = open(lockPath, O_CREAT | O_RDWR, 0o644)
    if fd >= 0 { flock(fd, LOCK_EX) }
    // Another launcher may have finished the job while we waited for the lock. A plist that
    // fails to parse here means the bundle is damaged mid-swap, not that someone else fixed
    // it, so fall back to the config already held rather than treating nil as "all clear".
    let fresh = readConfig(bundle: bundleURL) ?? config
    if cloneNeedsRebuild(fresh, bundleURL) {
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

let execURL = cloneExecutableURL(config: config, bundle: bundleURL, appURL: appURL)
guard FileManager.default.isExecutableFile(atPath: execURL.path) else {
    fail("This instance is incomplete (\(execURL.lastPathComponent) is missing). Open Duplex and edit the instance to rebuild it.")
}

if execURL.lastPathComponent == InstancePlist.launcherExecutable {
    fail("This instance points at another Duplex instance instead of the original app. Delete it and create it again from the original app.")
}

// Apps that keep their login outside the profile get a private folder of their own too.
// Each one must exist before the app starts, or the app falls back to the shared default.
let extraEnvironment = LauncherLogic.extraEnvironment(
    targetBundleID: config.targetBundleID, targetURL: appURL, dataDir: dataDir,
    fileExists: { FileManager.default.fileExists(atPath: $0) })
for (key, path) in extraEnvironment {
    do {
        try FileManager.default.createDirectory(atPath: path, withIntermediateDirectories: true)
    } catch {
        fail("Could not create the instance folder at \(path).")
    }
    setenv(key, path, 1)
}

let args = LauncherLogic.execArguments(targetExecutable: execURL.path, dataDir: dataDir)
var cargs: [UnsafeMutablePointer<CChar>?] = args.map { strdup($0) }
cargs.append(nil)
execv(args[0], cargs)
// execv only returns on failure.
fail("Failed to launch \(config.name) (errno \(errno)).")
