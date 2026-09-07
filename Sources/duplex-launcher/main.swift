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

/// The clone's own copy of the app binary, using the same fallback chain as WrapperGenerator:
/// the recorded executable name, then AppInspector on the original, then the app's base name.
func cloneExecutableURL(config: LauncherConfig, bundle: URL, appURL: URL) -> URL {
    let executableName = config.targetExecutable
        ?? (try? AppInspector.inspect(appURL))?.executable
        ?? appURL.deletingPathExtension().lastPathComponent
    return bundle.appendingPathComponent("Contents/MacOS").appendingPathComponent(executableName)
}

let installedVersion = InstancePlist.sourceVersion(ofBundleAt: appURL)

/// True when the original has updated since this clone was made, or the clone's own binary is
/// missing (an interrupted resync left it half-swapped).
func cloneNeedsRebuild(_ config: LauncherConfig, _ bundle: URL) -> Bool {
    LauncherLogic.needsResync(recorded: config.sourceVersion, installed: installedVersion)
        || !FileManager.default.isExecutableFile(
            atPath: cloneExecutableURL(config: config, bundle: bundle, appURL: appURL).path)
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

let args = LauncherLogic.execArguments(targetExecutable: execURL.path, dataDir: dataDir)
var cargs: [UnsafeMutablePointer<CChar>?] = args.map { strdup($0) }
cargs.append(nil)
execv(args[0], cargs)
// execv only returns on failure.
fail("Failed to launch \(config.name) (errno \(errno)).")
