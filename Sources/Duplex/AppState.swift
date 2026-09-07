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
    /// Backs `isBusy` with a count so overlapping busy operations (create, migration, quit)
    /// don't clear the flag for each other when one finishes before the others.
    private var busyCount = 0 {
        didSet { isBusy = busyCount > 0 }
    }
    private func beginBusy() { busyCount += 1 }
    private func endBusy() { busyCount -= 1 }
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
        guard !isBusy else {
            errorMessage = "Duplex is still working on another instance. Try again in a moment."
            return false
        }
        beginBusy()
        defer { endBusy() }
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
        beginBusy()
        defer { isMigrating = false; endBusy() }

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
            var notice = "Duplex updated \(migrated) \(noun) to the new format so each has its own identity. Because session storage changed, sign in again in each instance."
            if !failures.isEmpty {
                notice += "\n\nThese instances could not be updated:\n" + failures.joined(separator: "\n")
            }
            migrationNotice = notice
        } else if !failures.isEmpty {
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
        beginBusy()
        defer { endBusy() }
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
