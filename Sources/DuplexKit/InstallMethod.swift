import Foundation

/// How this copy of Duplex was installed, so the update notice can show the
/// step that actually applies to this user instead of guessing.
public enum InstallMethod: Equatable, Sendable {
    /// Installed from the Homebrew tap; upgrading is one command.
    case homebrew
    /// Installed from a downloaded zip; upgrading means downloading the new one.
    case direct

    /// Homebrew records every cask it installs under its Caskroom, on both
    /// Apple Silicon and Intel prefixes.
    static let caskroomPaths = [
        "/opt/homebrew/Caskroom/duplex",
        "/usr/local/Caskroom/duplex",
    ]

    public static func detect(
        fileExists: (String) -> Bool = { FileManager.default.fileExists(atPath: $0) }
    ) -> InstallMethod {
        caskroomPaths.contains(where: fileExists) ? .homebrew : .direct
    }
}
