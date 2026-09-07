import SwiftUI
import DuplexKit

@main
struct DuplexApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var state = AppState()
    @StateObject private var updates = UpdateManager(
        feed: GitHubReleaseFeed(url: DuplexConfig.releasesFeedURL),
        currentVersion: DuplexConfig.appVersion)

    var body: some Scene {
        WindowGroup("Duplex") {
            InstanceListView()
                .environmentObject(state)
                .environmentObject(state.license)
                .environmentObject(updates)
                .tint(DuplexTheme.indigo)
                .frame(minWidth: 640, minHeight: 420)
                .onAppear { state.refresh() }
                .task {
                    await updates.checkIfDue()
                    await state.license.revalidateIfDue()
                    if let notice = state.license.revocationNotice {
                        state.errorMessage = notice
                        state.license.revocationNotice = nil
                    }
                }
        }
        .windowResizability(.contentSize)
        .commands {
            CommandGroup(after: .appInfo) {
                Button("License\u{2026}") { state.showLicenseSheet = true }
                Divider()
                Button("Check for Updates Now") { Task { await updates.checkNow() } }
                Toggle("Check for Updates Automatically", isOn: Binding(
                    get: { updates.automaticChecksEnabled },
                    set: { updates.automaticChecksEnabled = $0 }))
            }
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Needed when run via `swift run` (no bundle): show in Dock, allow windows.
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}
