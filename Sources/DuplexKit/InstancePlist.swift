import Foundation

/// Turns a target app's own Info.plist into an instance plist. Pure: no filesystem access
/// except the one convenience reader at the bottom.
public enum InstancePlist {
    public static let launcherExecutable = "duplex-launcher"
    public static let iconFile = "icon.icns"

    /// Keys removed from clones: an Assets.car icon name would beat icon.icns in Finder, and
    /// document/UTI declarations would add "Open With" entries for every instance.
    static let removedKeys = [
        "CFBundleIconName", "CFBundleDocumentTypes",
        "UTExportedTypeDeclarations", "UTImportedTypeDeclarations",
    ]

    /// "<CFBundleShortVersionString> (<CFBundleVersion>)" of the target so a change to either
    /// triggers a re-sync. nil when the plist has neither.
    public static func sourceVersion(of plist: [String: Any]) -> String? {
        let short = plist["CFBundleShortVersionString"] as? String
        let build = plist["CFBundleVersion"] as? String
        switch (short, build) {
        case (nil, nil): return nil
        case (let s?, nil): return s
        case (nil, let b?): return "(\(b))"
        case (let s?, let b?): return "\(s) (\(b))"
        }
    }

    public static func sourceVersion(ofBundleAt url: URL) -> String? {
        let plistURL = url.appendingPathComponent("Contents/Info.plist")
        guard let data = try? Data(contentsOf: plistURL),
              let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any]
        else { return nil }
        return sourceVersion(of: plist)
    }

    /// Changes only identity, icon, executable and the Duplex bookkeeping keys. CFBundleName
    /// stays (Electron derives "<CFBundleName> Helper.app" from it) and so does
    /// ElectronAsarIntegrity.
    public static func patch(_ original: [String: Any], spec: InstanceSpec) -> [String: Any] {
        var plist = original
        plist["CFBundleIdentifier"] = DuplexPlistKey.bundleIDPrefix + spec.slug
        plist["CFBundleDisplayName"] = spec.name
        plist["CFBundleExecutable"] = launcherExecutable
        plist["CFBundleIconFile"] = iconFile
        for key in removedKeys { plist.removeValue(forKey: key) }
        plist[DuplexPlistKey.targetBundleID] = spec.target.bundleID
        plist[DuplexPlistKey.targetPath] = spec.target.url.path
        plist[DuplexPlistKey.targetExecutable] = spec.target.executable
        plist[DuplexPlistKey.instanceSlug] = spec.slug
        plist[DuplexPlistKey.instanceName] = spec.name
        plist[DuplexPlistKey.formatVersion] = DuplexPlistKey.currentFormatVersion
        if let version = sourceVersion(of: original) {
            plist[DuplexPlistKey.sourceVersion] = version
        }
        return plist
    }
}
