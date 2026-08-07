import SwiftUI

@main
struct DuplexApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var state = AppState()

    var body: some Scene {
        WindowGroup("Duplex") {
            InstanceListView()
                .environmentObject(state)
                .environmentObject(state.license)
                .tint(DuplexTheme.indigo)
                .frame(minWidth: 640, minHeight: 420)
                .onAppear { state.refresh() }
                .task {
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
