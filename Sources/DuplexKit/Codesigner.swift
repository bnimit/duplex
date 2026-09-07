import Foundation

/// Thin wrapper over /usr/bin/codesign. Ad-hoc only, one item at a time, never --deep: a
/// clone's helpers and binaries are signed explicitly, innermost first, and its frameworks keep
/// the vendor's signature.
public enum Codesigner {
    public static func adhocSign(_ url: URL) throws {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/codesign")
        p.arguments = ["--force", "-s", "-", url.path]
        let stderrPipe = Pipe()
        p.standardOutput = FileHandle.nullDevice
        p.standardError = stderrPipe
        try p.run()
        let stderrData = stderrPipe.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        guard p.terminationStatus == 0 else {
            let message = String(decoding: stderrData, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
            throw WrapperGeneratorError.codesignFailed(p.terminationStatus, message)
        }
    }

    /// "adhoc" for an ad-hoc signature, "signed" for any other valid signature, nil when the
    /// item is unsigned or unreadable. Parses `codesign -dv`, which reports on stderr.
    public static func signatureKind(_ url: URL) -> String? {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/codesign")
        p.arguments = ["-dv", url.path]
        let pipe = Pipe()
        p.standardOutput = FileHandle.nullDevice
        p.standardError = pipe
        guard (try? p.run()) != nil else { return nil }
        let output = String(decoding: pipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        p.waitUntilExit()
        guard p.terminationStatus == 0 else { return nil }
        return output.contains("Signature=adhoc") ? "adhoc" : "signed"
    }
}
