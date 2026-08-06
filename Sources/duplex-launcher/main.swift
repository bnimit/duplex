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

guard let info = Bundle.main.infoDictionary,
      let config = LauncherLogic.config(from: info) else {
    fail("This wrapper is missing its Duplex configuration. Recreate the instance in Duplex.")
}

// Resolve the target app: prefer LaunchServices (survives moves/updates), fall back to the recorded path.
let appURL = LauncherLogic.resolveTarget(
    lsResolved: NSWorkspace.shared.urlForApplication(withBundleIdentifier: config.targetBundleID),
    fallbackPath: config.targetPath,
    fileExists: { FileManager.default.fileExists(atPath: $0) })
guard let appURL = appURL else {
    fail("The original app (\(config.targetBundleID)) could not be found. Was it uninstalled?")
}

guard let execURL = Bundle(url: appURL)?.executableURL else {
    fail("The original app at \(appURL.path) has no executable.")
}

// $HOME env var by design: launched normally it's the real home, and tests can redirect it.
let home = ProcessInfo.processInfo.environment["HOME"] ?? NSHomeDirectory()
let dataDir = LauncherLogic.dataDir(slug: config.slug, homePath: home)
do {
    try FileManager.default.createDirectory(at: dataDir, withIntermediateDirectories: true)
} catch {
    fail("Could not create the instance data folder at \(dataDir.path).")
}

let args = LauncherLogic.execArguments(targetExecutable: execURL.path, dataDir: dataDir)
var cargs: [UnsafeMutablePointer<CChar>?] = args.map { strdup($0) }
cargs.append(nil)
execv(args[0], cargs)
// execv only returns on failure.
fail("Failed to launch \(appURL.lastPathComponent) (errno \(errno)).")
