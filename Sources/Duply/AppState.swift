import AppKit
import SwiftUI
import DuplyKit

@MainActor
final class AppState: ObservableObject {
    @Published var instances: [Instance] = []
    @Published var dataSizes: [String: Int64] = [:]
    @Published var errorMessage: String?

    let outputDir = WrapperGenerator.defaultOutputDir()
    private var homePath: String { ProcessInfo.processInfo.environment["HOME"] ?? NSHomeDirectory() }

    func refresh() {
        instances = InstanceStore.scan(outputDir: outputDir, homePath: homePath)
        var sizes: [String: Int64] = [:]
        for instance in instances {
            sizes[instance.slug] = InstanceStore.dataSize(of: instance)
        }
        dataSizes = sizes
    }

    /// The launcher binary: inside Duply.app it's bundled in Resources;
    /// during `swift run` it sits next to the Duply executable in .build/.
    static func launcherURL() -> URL? {
        if let bundled = Bundle.main.url(forResource: "duply-launcher", withExtension: nil) {
            return bundled
        }
        let sibling = URL(fileURLWithPath: CommandLine.arguments[0])
            .deletingLastPathComponent()
            .appendingPathComponent("duply-launcher")
        return FileManager.default.isExecutableFile(atPath: sibling.path) ? sibling : nil
    }

    func create(name: String, appURL: URL, icon: IconChoice, existingSlug: String? = nil) {
        do {
            guard let launcher = Self.launcherURL() else {
                throw NSError(domain: "Duply", code: 1, userInfo: [
                    NSLocalizedDescriptionKey: "duply-launcher binary not found. Build it with `swift build` or run from Duply.app."])
            }
            let target = try AppInspector.inspect(appURL)
            let slug = existingSlug ?? SlugGenerator.slug(from: name, existing: Set(instances.map(\.slug)))
            let spec = InstanceSpec(name: name, slug: slug, target: target)
            try WrapperGenerator(launcherBinary: launcher).generate(spec: spec, icon: icon, outputDir: outputDir)
            refresh()
        } catch {
            errorMessage = error.localizedDescription
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

    /// Launches the ORIGINAL app (default profile) by spawning its binary directly,
    /// bypassing LaunchServices — so it works even while a cloned instance is running
    /// (LS would otherwise just focus the clone). Makes launch order irrelevant.
    func launchOriginal(_ instance: Instance) {
        guard let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: instance.targetBundleID)
                ?? (FileManager.default.fileExists(atPath: instance.targetPath)
                    ? URL(fileURLWithPath: instance.targetPath) : nil),
              let execURL = Bundle(url: appURL)?.executableURL else {
            errorMessage = "The original app (\(instance.targetBundleID)) could not be found."
            return
        }
        let p = Process()
        p.executableURL = execURL
        do { try p.run() } catch { errorMessage = error.localizedDescription }
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
