import Foundation

public enum BundleClonerError: Error, LocalizedError {
    case destinationExists(String)
    public var errorDescription: String? {
        switch self {
        case .destinationExists(let path): return "\(path) already exists."
        }
    }
}

/// Filesystem primitives for building an instance out of a target app bundle.
public enum BundleCloner {
    /// Copy-on-write clone of a whole tree via clonefile(2): sub-second and shares disk blocks
    /// with the source. Falls back to a regular recursive copy when the volume refuses
    /// (different volume, non-APFS).
    public static func clone(_ source: URL, to destination: URL) throws {
        if FileManager.default.fileExists(atPath: destination.path) {
            throw BundleClonerError.destinationExists(destination.path)
        }
        if clonefile(source.path, destination.path, 0) == 0 { return }
        try FileManager.default.copyItem(at: source, to: destination)
    }

    /// Removes com.apple.quarantine from every item in the tree. A clone inherits the
    /// original's attributes, and Gatekeeper refuses a quarantined ad-hoc bundle. Errors are
    /// ignored: most files simply do not carry the attribute.
    public static func stripQuarantine(at root: URL) {
        let name = "com.apple.quarantine"
        removexattr(root.path, name, XATTR_NOFOLLOW)
        guard let enumerator = FileManager.default.enumerator(
            at: root, includingPropertiesForKeys: nil, options: []) else { return }
        for case let url as URL in enumerator {
            removexattr(url.path, name, XATTR_NOFOLLOW)
        }
    }

    /// Regular files directly inside `dir` (not recursive), sorted by name. Subdirectories are
    /// left out.
    public static func looseFiles(in dir: URL) -> [URL] {
        let items = (try? FileManager.default.contentsOfDirectory(
            at: dir, includingPropertiesForKeys: [.isRegularFileKey], options: [])) ?? []
        return items
            .filter { url in
                (try? url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) ?? false
            }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
    }
}
