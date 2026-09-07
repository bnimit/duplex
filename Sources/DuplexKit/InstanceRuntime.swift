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
