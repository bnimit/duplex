import AppKit
import CoreServices

public enum WrapperGeneratorError: Error, LocalizedError {
    case codesignFailed(Int32)
    case destinationOccupied(String)

    public var errorDescription: String? {
        switch self {
        case .codesignFailed(let status):
            return "codesign failed with exit status \(status)."
        case .destinationOccupied(let name):
            return "\(name).app already exists there and isn't this instance's wrapper — pick a different instance name."
        }
    }
}

public struct WrapperGenerator {
    public let launcherBinary: URL

    public init(launcherBinary: URL) {
        self.launcherBinary = launcherBinary
    }

    @discardableResult
    public func generate(spec: InstanceSpec, icon: IconChoice, outputDir: URL) throws -> URL {
        let fm = FileManager.default
        try fm.createDirectory(at: outputDir, withIntermediateDirectories: true)

        // Locate this slug's existing wrapper (if any) — replaced only after the new build succeeds.
        let oldWrapper = ((try? fm.contentsOfDirectory(at: outputDir, includingPropertiesForKeys: nil)) ?? [])
            .first { $0.pathExtension == "app"
                && !$0.lastPathComponent.hasPrefix(".")
                && wrapperSlug(of: $0) == spec.slug }

        // Never overwrite a bundle that isn't this instance's wrapper (a real app, or another instance).
        let wrapper = outputDir.appendingPathComponent("\(spec.name).app")
        if fm.fileExists(atPath: wrapper.path), wrapperSlug(of: wrapper) != spec.slug {
            throw WrapperGeneratorError.destinationOccupied(spec.name)
        }

        // Stage the new bundle, sign it, and only then swap it in.
        let staging = outputDir.appendingPathComponent(".duplex-staging-\(spec.slug).app")
        if fm.fileExists(atPath: staging.path) { try fm.removeItem(at: staging) }
        do {
            try build(spec: spec, icon: icon, oldWrapper: oldWrapper, at: staging)
            try codesign(staging)
        } catch {
            try? fm.removeItem(at: staging)
            throw error
        }

        if let oldWrapper, fm.fileExists(atPath: oldWrapper.path) { try fm.removeItem(at: oldWrapper) }
        if fm.fileExists(atPath: wrapper.path) { try fm.removeItem(at: wrapper) } // only reachable for same-slug leftovers
        try fm.moveItem(at: staging, to: wrapper)
        LSRegisterURL(wrapper as CFURL, true)
        return wrapper
    }

    private func wrapperSlug(of bundle: URL) -> String? {
        let plistURL = bundle.appendingPathComponent("Contents/Info.plist")
        guard let data = try? Data(contentsOf: plistURL),
              let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any]
        else { return nil }
        return plist[DuplexPlistKey.instanceSlug] as? String
    }

    private func build(spec: InstanceSpec, icon: IconChoice, oldWrapper: URL?, at bundleURL: URL) throws {
        let fm = FileManager.default
        let contents = bundleURL.appendingPathComponent("Contents")
        try fm.createDirectory(at: contents.appendingPathComponent("MacOS"), withIntermediateDirectories: true)
        try fm.createDirectory(at: contents.appendingPathComponent("Resources"), withIntermediateDirectories: true)

        let plistData = try PropertyListSerialization.data(
            fromPropertyList: WrapperPlist.plist(for: spec), format: .xml, options: 0)
        try plistData.write(to: contents.appendingPathComponent("Info.plist"))
        try Data("APPL????".utf8).write(to: contents.appendingPathComponent("PkgInfo"))

        let exec = contents.appendingPathComponent("MacOS/duplex-launcher")
        try fm.copyItem(at: launcherBinary, to: exec)
        try fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: exec.path)

        // Icon must be written before codesign — the signature seals Resources.
        let iconDestination = contents.appendingPathComponent("Resources/icon.icns")
        switch icon {
        case .badge(let color):
            let image = IconBadger.badged(NSWorkspace.shared.icon(forFile: spec.target.url.path), color: color)
            try IconBadger.writeICNS(image, to: iconDestination)
        case .custom(let url):
            let image = try IconBadger.loadImage(at: url)
            try IconBadger.writeICNS(image, to: iconDestination)
        case .keepExisting:
            let oldIcon = oldWrapper?.appendingPathComponent("Contents/Resources/icon.icns")
            if let oldIcon, fm.fileExists(atPath: oldIcon.path) {
                try fm.copyItem(at: oldIcon, to: iconDestination)
            } else {
                // No prior wrapper to copy from (e.g. first-time generation) — fall back to badge(.blue).
                let image = IconBadger.badged(NSWorkspace.shared.icon(forFile: spec.target.url.path), color: .blue)
                try IconBadger.writeICNS(image, to: iconDestination)
            }
        }
    }

    private func codesign(_ bundle: URL) throws {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/codesign")
        p.arguments = ["--force", "--deep", "-s", "-", bundle.path]
        p.standardOutput = FileHandle.nullDevice
        p.standardError = FileHandle.nullDevice
        try p.run()
        p.waitUntilExit()
        guard p.terminationStatus == 0 else { throw WrapperGeneratorError.codesignFailed(p.terminationStatus) }
    }

    public static func defaultOutputDir() -> URL {
        let applications = URL(fileURLWithPath: "/Applications")
        if FileManager.default.isWritableFile(atPath: applications.path) { return applications }
        let userApps = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Applications")
        try? FileManager.default.createDirectory(at: userApps, withIntermediateDirectories: true)
        return userApps
    }
}
