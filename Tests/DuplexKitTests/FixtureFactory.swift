import Foundation

enum FixtureFactory {
    /// Builds a minimal fake .app bundle. If electron: true, adds
    /// Contents/Frameworks/Electron Framework.framework/.
    /// The executable is a bash script that records its argv to
    /// <bundle-parent>/args.txt (used by the Task 10 E2E test).
    @discardableResult
    static func makeFakeApp(
        named name: String,
        bundleID: String,
        electron: Bool,
        schemes: [String] = [],
        in dir: URL
    ) throws -> URL {
        let app = dir.appendingPathComponent("\(name).app")
        let macos = app.appendingPathComponent("Contents/MacOS")
        try FileManager.default.createDirectory(at: macos, withIntermediateDirectories: true)

        var plist: [String: Any] = [
            "CFBundleIdentifier": bundleID,
            "CFBundleName": name,
            "CFBundleExecutable": name,
            "CFBundlePackageType": "APPL",
        ]
        if !schemes.isEmpty {
            plist["CFBundleURLTypes"] = [["CFBundleURLName": name, "CFBundleURLSchemes": schemes]]
        }
        let plistData = try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
        try plistData.write(to: app.appendingPathComponent("Contents/Info.plist"))

        let script = "#!/bin/bash\necho \"$@\" > \"$(dirname \"$0\")/../../../args.txt\"\n"
        let exec = macos.appendingPathComponent(name)
        try script.write(to: exec, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: exec.path)

        if electron {
            let fw = app.appendingPathComponent("Contents/Frameworks/Electron Framework.framework")
            try FileManager.default.createDirectory(at: fw, withIntermediateDirectories: true)
        }
        return app
    }

    static func tempDir(_ testName: String) throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("duplex-tests-\(testName)-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}
