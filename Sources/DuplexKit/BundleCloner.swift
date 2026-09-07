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

    /// True when the file starts with a Mach-O or fat-binary magic number.
    public static func isMachO(_ url: URL) -> Bool {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return false }
        defer { try? handle.close() }
        guard let data = try? handle.read(upToCount: 4), data.count == 4 else { return false }
        let magic = data.withUnsafeBytes { $0.loadUnaligned(as: UInt32.self) }
        let known: [UInt32] = [0xfeedfacf, 0xcffaedfe, 0xfeedface, 0xcefaedfe, 0xcafebabe, 0xbebafeca]
        return known.contains(magic)
    }

    /// Regular Mach-O files directly inside `dir` (not recursive), sorted by name. Scripts and
    /// other non-Mach-O files are left out because they cannot carry an embedded signature.
    public static func machOExecutables(in dir: URL) -> [URL] {
        let items = (try? FileManager.default.contentsOfDirectory(
            at: dir, includingPropertiesForKeys: [.isRegularFileKey], options: [])) ?? []
        return items
            .filter { url in
                let regular = (try? url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) ?? false
                return regular && isMachO(url)
            }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
    }
}
