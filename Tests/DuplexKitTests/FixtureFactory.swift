import Foundation
import DuplexKit

enum FixtureFactory {
    /// Builds a minimal fake .app bundle. If electron: true, adds
    /// Contents/Frameworks/Electron Framework.framework/.
    /// The executable is a bash script that records "$0 $@" (its own path, then argv) to
    /// <bundle-parent>/args.txt, so tests can see where it ran from and with which flags.
    /// Optional extras mirror what real Electron apps ship: a helper app and a second Mach-O
    /// in MacOS (both copies of /bin/ls so codesign works), a provisioning profile, an
    /// Assets.car icon name, and document types.
    @discardableResult
    static func makeFakeApp(
        named name: String,
        bundleID: String,
        electron: Bool,
        schemes: [String] = [],
        helper: Bool = false,
        nativeExecutable: Bool = false,
        provisionProfile: Bool = false,
        iconName: String? = nil,
        documentTypes: Bool = false,
        in dir: URL
    ) throws -> URL {
        let fm = FileManager.default
        let app = dir.appendingPathComponent("\(name).app")
        let contents = app.appendingPathComponent("Contents")
        let macos = contents.appendingPathComponent("MacOS")
        try fm.createDirectory(at: macos, withIntermediateDirectories: true)

        var plist: [String: Any] = [
            "CFBundleIdentifier": bundleID,
            "CFBundleName": name,
            "CFBundleExecutable": name,
            "CFBundlePackageType": "APPL",
            "CFBundleShortVersionString": "1.0",
            "CFBundleVersion": "100",
        ]
        if !schemes.isEmpty {
            plist["CFBundleURLTypes"] = [["CFBundleURLName": name, "CFBundleURLSchemes": schemes]]
        }
        if let iconName { plist["CFBundleIconName"] = iconName }
        if documentTypes {
            plist["CFBundleDocumentTypes"] = [["CFBundleTypeName": "Thing", "CFBundleTypeExtensions": ["thing"]]]
        }
        let plistData = try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
        try plistData.write(to: contents.appendingPathComponent("Info.plist"))

        let script = "#!/bin/bash\necho \"$0 $@\" > \"$(dirname \"$0\")/../../../args.txt\"\n"
        let exec = macos.appendingPathComponent(name)
        try script.write(to: exec, atomically: true, encoding: .utf8)
        try fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: exec.path)

        if electron {
            // A real Mach-O (a copy of /bin/ls, so it carries a real embedded signature, standing
            // in for the vendor's own) rather than a bare directory: an empty ".framework" is not
            // a well-formed nested bundle, and codesign refuses to validate the outer app at all
            // if one is sitting under Frameworks.
            let fw = contents.appendingPathComponent("Frameworks/Electron Framework.framework")
            try fm.createDirectory(at: fw, withIntermediateDirectories: true)
            try fm.copyItem(at: URL(fileURLWithPath: "/bin/ls"), to: fw.appendingPathComponent("Electron Framework"))
        }
        if helper {
            let helperApp = contents.appendingPathComponent("Frameworks/\(name) Helper.app")
            let helperMacOS = helperApp.appendingPathComponent("Contents/MacOS")
            try fm.createDirectory(at: helperMacOS, withIntermediateDirectories: true)
            let helperPlist: [String: Any] = [
                "CFBundleIdentifier": bundleID + ".helper",
                "CFBundleName": "\(name) Helper",
                "CFBundleExecutable": "\(name) Helper",
                "CFBundlePackageType": "APPL",
            ]
            try PropertyListSerialization.data(fromPropertyList: helperPlist, format: .xml, options: 0)
                .write(to: helperApp.appendingPathComponent("Contents/Info.plist"))
            try fm.copyItem(at: URL(fileURLWithPath: "/bin/ls"),
                            to: helperMacOS.appendingPathComponent("\(name) Helper"))
        }
        if nativeExecutable {
            try fm.copyItem(at: URL(fileURLWithPath: "/bin/ls"), to: macos.appendingPathComponent("\(name)-native"))
        }
        if provisionProfile {
            try Data("fake profile".utf8).write(to: contents.appendingPathComponent("embedded.provisionprofile"))
        }
        return app
    }

    /// Rewrites the version keys of a fixture app, simulating an app update.
    static func setVersion(of app: URL, short: String, build: String) throws {
        let plistURL = app.appendingPathComponent("Contents/Info.plist")
        var plist = try PropertyListSerialization.propertyList(
            from: try Data(contentsOf: plistURL), format: nil) as! [String: Any]
        plist["CFBundleShortVersionString"] = short
        plist["CFBundleVersion"] = build
        try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0).write(to: plistURL)
    }

    static func tempDir(_ testName: String) throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("duplex-tests-\(testName)-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    /// A 1.1-format wrapper plist (no DuplexFormatVersion) for legacy-detection and staging tests.
    static func legacyDuplexPlist(spec: InstanceSpec) -> [String: Any] {
        [
            "CFBundleIdentifier": DuplexPlistKey.bundleIDPrefix + spec.slug,
            "CFBundleName": spec.name,
            "CFBundleExecutable": "duplex-launcher",
            DuplexPlistKey.targetBundleID: spec.target.bundleID,
            DuplexPlistKey.targetPath: spec.target.url.path,
            DuplexPlistKey.instanceSlug: spec.slug,
            DuplexPlistKey.instanceName: spec.name,
        ]
    }
}
