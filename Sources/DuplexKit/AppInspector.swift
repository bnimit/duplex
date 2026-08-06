import Foundation

public struct TargetApp: Equatable {
    public let url: URL
    public let bundleID: String
    public let name: String
    public let executable: String
    public let urlSchemes: [String]

    public init(url: URL, bundleID: String, name: String, executable: String, urlSchemes: [String]) {
        self.url = url
        self.bundleID = bundleID
        self.name = name
        self.executable = executable
        self.urlSchemes = urlSchemes
    }
}

public enum AppInspectorError: Error, Equatable, LocalizedError {
    case missingInfoPlist
    case missingKey(String)
    case notElectron(String)

    public var errorDescription: String? {
        switch self {
        case .missingInfoPlist:
            return "This doesn't look like an app bundle (no Info.plist)."
        case .missingKey(let key):
            return "The app's Info.plist is missing \(key)."
        case .notElectron(let name):
            return "\(name) isn't an Electron-based app. Duplex's isolation technique (--user-data-dir) only works for Electron/Chromium apps like Claude, Slack, Discord, Signal, or VS Code."
        }
    }
}

public enum AppInspector {
    public static func isElectronBased(_ appURL: URL) -> Bool {
        let fw = appURL.appendingPathComponent("Contents/Frameworks/Electron Framework.framework")
        return FileManager.default.fileExists(atPath: fw.path)
    }

    public static func inspect(_ appURL: URL) throws -> TargetApp {
        let plistURL = appURL.appendingPathComponent("Contents/Info.plist")
        guard let data = try? Data(contentsOf: plistURL),
              let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any]
        else { throw AppInspectorError.missingInfoPlist }

        let fallbackName = appURL.deletingPathExtension().lastPathComponent
        let name = plist["CFBundleName"] as? String ?? fallbackName

        guard isElectronBased(appURL) else { throw AppInspectorError.notElectron(name) }
        guard let bundleID = plist["CFBundleIdentifier"] as? String else {
            throw AppInspectorError.missingKey("CFBundleIdentifier")
        }
        guard let executable = plist["CFBundleExecutable"] as? String else {
            throw AppInspectorError.missingKey("CFBundleExecutable")
        }

        var schemes: [String] = []
        if let urlTypes = plist["CFBundleURLTypes"] as? [[String: Any]] {
            for entry in urlTypes {
                schemes.append(contentsOf: entry["CFBundleURLSchemes"] as? [String] ?? [])
            }
        }
        return TargetApp(url: appURL, bundleID: bundleID, name: name, executable: executable, urlSchemes: schemes)
    }
}
