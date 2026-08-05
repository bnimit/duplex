import AppKit
import CoreServices

public enum WrapperGeneratorError: Error, LocalizedError {
    case codesignFailed(Int32)
    public var errorDescription: String? {
        switch self {
        case .codesignFailed(let status): return "codesign failed with exit status \(status)."
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

        // Regenerate in place: remove any existing wrapper carrying this slug (name may have changed).
        for existing in (try? fm.contentsOfDirectory(at: outputDir, includingPropertiesForKeys: nil)) ?? []
        where existing.pathExtension == "app" {
            let plistURL = existing.appendingPathComponent("Contents/Info.plist")
            if let data = try? Data(contentsOf: plistURL),
               let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
               plist[DuplyPlistKey.instanceSlug] as? String == spec.slug {
                try fm.removeItem(at: existing)
            }
        }

        let wrapper = outputDir.appendingPathComponent("\(spec.name).app")
        if fm.fileExists(atPath: wrapper.path) { try fm.removeItem(at: wrapper) }
        let contents = wrapper.appendingPathComponent("Contents")
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

        try codesign(wrapper)
        LSRegisterURL(wrapper as CFURL, true) // make LaunchServices aware (URL-scheme routing)
        return wrapper
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
