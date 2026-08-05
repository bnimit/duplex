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
            .first { $0.pathExtension == "app" && wrapperSlug(of: $0) == spec.slug }

        // Never overwrite a bundle that isn't this instance's wrapper (a real app, or another instance).
        let wrapper = outputDir.appendingPathComponent("\(spec.name).app")
        if fm.fileExists(atPath: wrapper.path), wrapperSlug(of: wrapper) != spec.slug {
            throw WrapperGeneratorError.destinationOccupied(spec.name)
        }

        // Stage the new bundle, sign it, and only then swap it in.
        let staging = outputDir.appendingPathComponent(".duply-staging-\(spec.slug).app")
        if fm.fileExists(atPath: staging.path) { try fm.removeItem(at: staging) }
        do {
            try build(spec: spec, icon: icon, at: staging)
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
        return plist[DuplyPlistKey.instanceSlug] as? String
    }

    private func build(spec: InstanceSpec, icon: IconChoice, at bundleURL: URL) throws {
        let fm = FileManager.default
        let contents = bundleURL.appendingPathComponent("Contents")
        try fm.createDirectory(at: contents.appendingPathComponent("MacOS"), withIntermediateDirectories: true)
        try fm.createDirectory(at: contents.appendingPathComponent("Resources"), withIntermediateDirectories: true)

        let plistData = try PropertyListSerialization.data(
            fromPropertyList: WrapperPlist.plist(for: spec), format: .xml, options: 0)
        try plistData.write(to: contents.appendingPathComponent("Info.plist"))
        try Data("APPL????".utf8).write(to: contents.appendingPathComponent("PkgInfo"))

        let exec = contents.appendingPathComponent("MacOS/duply-launcher")
        try fm.copyItem(at: launcherBinary, to: exec)
        try fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: exec.path)

        let iconImage: NSImage
        switch icon {
        case .badge(let color):
            iconImage = IconBadger.badged(NSWorkspace.shared.icon(forFile: spec.target.url.path), color: color)
        case .custom(let url):
            iconImage = try IconBadger.loadImage(at: url)
        }
        try IconBadger.writeICNS(iconImage, to: contents.appendingPathComponent("Resources/icon.icns"))
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
