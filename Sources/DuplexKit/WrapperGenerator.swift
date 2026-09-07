import AppKit
import CoreServices

public enum WrapperGeneratorError: Error, LocalizedError {
    case codesignFailed(Int32)
    case destinationOccupied(String)
    case unreadablePlist(String)

    public var errorDescription: String? {
        switch self {
        case .codesignFailed(let status):
            return "codesign failed with exit status \(status)."
        case .destinationOccupied(let name):
            return "\(name).app already exists there and isn't this instance's wrapper, pick a different instance name."
        case .unreadablePlist(let path):
            return "The app's Info.plist at \(path) could not be read."
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

        // Locate this slug's existing wrapper (if any), replaced only after the new build succeeds.
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

    /// The instance is a copy-on-write clone of the target app whose identity is patched:
    /// only the Info.plist keys InstancePlist changes, the launcher, and the icon differ from
    /// the original. Running the app's binary from inside this clone is what gives the
    /// instance its own identity to LaunchServices.
    private func build(spec: InstanceSpec, icon: IconChoice, oldWrapper: URL?, at bundleURL: URL) throws {
        let fm = FileManager.default
        try BundleCloner.clone(spec.target.url, to: bundleURL)
        BundleCloner.stripQuarantine(at: bundleURL)
        let contents = bundleURL.appendingPathComponent("Contents")

        let plistURL = contents.appendingPathComponent("Info.plist")
        guard let data = try? Data(contentsOf: plistURL),
              let original = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any]
        else { throw WrapperGeneratorError.unreadablePlist(plistURL.path) }
        let patched = InstancePlist.patch(original, spec: spec)
        try PropertyListSerialization.data(fromPropertyList: patched, format: .xml, options: 0).write(to: plistURL)

        let pkgInfo = contents.appendingPathComponent("PkgInfo")
        if !fm.fileExists(atPath: pkgInfo.path) { try Data("APPL????".utf8).write(to: pkgInfo) }

        // Ad-hoc code cannot use a provisioning profile; leaving it would only confuse validation.
        let profile = contents.appendingPathComponent("embedded.provisionprofile")
        if fm.fileExists(atPath: profile.path) { try fm.removeItem(at: profile) }

        let exec = contents.appendingPathComponent("MacOS").appendingPathComponent(InstancePlist.launcherExecutable)
        if fm.fileExists(atPath: exec.path) { try fm.removeItem(at: exec) }
        try fm.copyItem(at: launcherBinary, to: exec)
        try fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: exec.path)

        // Icon must be written before codesign; the signature seals Resources.
        let resources = contents.appendingPathComponent("Resources")
        try fm.createDirectory(at: resources, withIntermediateDirectories: true)
        try writeIcon(icon, spec: spec, oldWrapper: oldWrapper, to: resources.appendingPathComponent(InstancePlist.iconFile))
    }

    private func writeIcon(_ icon: IconChoice, spec: InstanceSpec, oldWrapper: URL?, to iconDestination: URL) throws {
        let fm = FileManager.default
        switch icon {
        case .original:
            if let sourceIcns = originalIconURL(for: spec.target) {
                try fm.copyItem(at: sourceIcns, to: iconDestination)
            } else {
                // No usable .icns on the target (e.g. Assets.car-only app): fall back to a
                // rendered, unbadged icon.
                let icon = IconBadger.normalizedIcon(NSWorkspace.shared.icon(forFile: spec.target.url.path))
                try IconBadger.writeICNS(icon, to: iconDestination)
            }
        case .badge(let color):
            let icon = IconBadger.normalizedIcon(NSWorkspace.shared.icon(forFile: spec.target.url.path))
            let image = IconBadger.badged(icon, color: color)
            try IconBadger.writeICNS(image, to: iconDestination)
        case .custom(let url):
            let image = try IconBadger.loadImage(at: url)
            try IconBadger.writeICNS(image, to: iconDestination)
        case .keepExisting:
            let oldIcon = oldWrapper?.appendingPathComponent("Contents/Resources").appendingPathComponent(InstancePlist.iconFile)
            if let oldIcon, fm.fileExists(atPath: oldIcon.path) {
                try fm.copyItem(at: oldIcon, to: iconDestination)
            } else {
                // No prior wrapper to copy from (e.g. first-time generation): fall back to badge(.blue).
                let icon = IconBadger.normalizedIcon(NSWorkspace.shared.icon(forFile: spec.target.url.path))
                let image = IconBadger.badged(icon, color: .blue)
                try IconBadger.writeICNS(image, to: iconDestination)
            }
        }
    }

    /// Locates the target app's own .icns file via its `CFBundleIconFile` Info.plist key.
    /// Returns nil when the plist, key, or file is missing/unreadable (e.g. Assets.car-only apps).
    private func originalIconURL(for target: TargetApp) -> URL? {
        let plistURL = target.url.appendingPathComponent("Contents/Info.plist")
        guard let data = try? Data(contentsOf: plistURL),
              let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
              var iconFile = plist["CFBundleIconFile"] as? String,
              !iconFile.isEmpty
        else { return nil }
        if !iconFile.lowercased().hasSuffix(".icns") { iconFile += ".icns" }
        let iconURL = target.url.appendingPathComponent("Contents/Resources/\(iconFile)")
        return FileManager.default.fileExists(atPath: iconURL.path) ? iconURL : nil
    }

    /// Innermost first: helper apps, then every regular file directly in MacOS other than the
    /// launcher (the target's own binary, and anything else the app ships there, Mach-O or
    /// not), then the launcher, then the bundle. Ad-hoc-signing the launcher, which is
    /// CFBundleExecutable, puts codesign into bundle-validation mode, which requires every
    /// sibling file in MacOS to already carry some signature; codesign can ad-hoc-sign a
    /// non-Mach-O file too (a generic-format signature), so a script main executable such as
    /// the target's original binary is signed the same way. Chromium requires the browser and
    /// its helpers to share a signing identity, and ad-hoc for all of them satisfies that.
    /// Frameworks are not touched and keep the vendor's signature.
    private func codesign(_ bundle: URL) throws {
        let fm = FileManager.default
        let contents = bundle.appendingPathComponent("Contents")
        let frameworks = contents.appendingPathComponent("Frameworks")
        let helpers = ((try? fm.contentsOfDirectory(at: frameworks, includingPropertiesForKeys: nil)) ?? [])
            .filter { $0.pathExtension == "app" }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
        for helper in helpers { try Codesigner.adhocSign(helper) }

        let macos = contents.appendingPathComponent("MacOS")
        let items = ((try? fm.contentsOfDirectory(at: macos, includingPropertiesForKeys: [.isRegularFileKey])) ?? [])
            .filter { (try? $0.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) ?? false }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
        for item in items where item.lastPathComponent != InstancePlist.launcherExecutable {
            try Codesigner.adhocSign(item)
        }
        if let launcher = items.first(where: { $0.lastPathComponent == InstancePlist.launcherExecutable }) {
            try Codesigner.adhocSign(launcher)
        }
        try Codesigner.adhocSign(bundle)
    }

    public static func defaultOutputDir() -> URL {
        let applications = URL(fileURLWithPath: "/Applications")
        if FileManager.default.isWritableFile(atPath: applications.path) { return applications }
        let userApps = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Applications")
        try? FileManager.default.createDirectory(at: userApps, withIntermediateDirectories: true)
        return userApps
    }
}
