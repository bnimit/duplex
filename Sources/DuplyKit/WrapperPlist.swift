import Foundation

public enum WrapperPlist {
    public static func plist(for spec: InstanceSpec) -> [String: Any] {
        var plist: [String: Any] = [
            "CFBundleIdentifier": DuplyPlistKey.bundleIDPrefix + spec.slug,
            "CFBundleName": spec.name,
            "CFBundleDisplayName": spec.name,
            "CFBundleExecutable": "duply-launcher",
            "CFBundlePackageType": "APPL",
            "CFBundleIconFile": "icon",
            "CFBundleShortVersionString": "1.0",
            "CFBundleVersion": "1",
            "LSMinimumSystemVersion": "12.0",
            "NSHighResolutionCapable": true,
            DuplyPlistKey.targetBundleID: spec.target.bundleID,
            DuplyPlistKey.targetPath: spec.target.url.path,
            DuplyPlistKey.instanceSlug: spec.slug,
            DuplyPlistKey.instanceName: spec.name,
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
