import Foundation

public enum WrapperPlist {
    public static func plist(for spec: InstanceSpec) -> [String: Any] {
        var plist: [String: Any] = [
            "CFBundleIdentifier": DuplexPlistKey.bundleIDPrefix + spec.slug,
            "CFBundleName": spec.name,
            "CFBundleDisplayName": spec.name,
            "CFBundleExecutable": "duplex-launcher",
            "CFBundlePackageType": "APPL",
            "CFBundleIconFile": "icon",
            "CFBundleShortVersionString": "1.0",
            "CFBundleVersion": "1",
            "LSMinimumSystemVersion": "13.0",
            "NSHighResolutionCapable": true,
            DuplexPlistKey.targetBundleID: spec.target.bundleID,
            DuplexPlistKey.targetPath: spec.target.url.path,
            DuplexPlistKey.instanceSlug: spec.slug,
            DuplexPlistKey.instanceName: spec.name,
        ]
        if !spec.target.urlSchemes.isEmpty {
            plist["CFBundleURLTypes"] = [[
                "CFBundleURLName": spec.name,
                "CFBundleURLSchemes": spec.target.urlSchemes,
            ] as [String: Any]]
        }
        return plist
    }
}
