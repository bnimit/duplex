import AppKit
import DuplyKit

func fail(_ message: String) -> Never {
    CFUserNotificationDisplayAlert(
        0, kCFUserNotificationCautionAlertLevel,
        nil, nil, nil,
        "Duply" as CFString, message as CFString,
        nil, nil, nil, nil)
    exit(1)
}

guard let info = Bundle.main.infoDictionary,
      let config = LauncherLogic.config(from: info) else {
    fail("This wrapper is missing its Duply configuration. Recreate the instance in Duply.")
}

// Resolve the target app: prefer LaunchServices (survives moves/updates), fall back to the recorded path.
var targetURL: URL?
if let resolved = NSWorkspace.shared.urlForApplication(withBundleIdentifier: config.targetBundleID),
   FileManager.default.fileExists(atPath: resolved.path) {
    targetURL = resolved
} else if FileManager.default.fileExists(atPath: config.targetPath) {
    targetURL = URL(fileURLWithPath: config.targetPath)
}
guard let appURL = targetURL else {
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
