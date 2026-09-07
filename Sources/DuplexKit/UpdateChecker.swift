import Foundation

/// A release newer than the running build.
public struct AvailableUpdate: Equatable, Sendable {
    public let version: String
    /// Where to send the user to read about it and download.
    public let url: URL

    public init(version: String, url: URL) {
        self.version = version
        self.url = url
    }
}

public enum UpdateCheckError: Error, LocalizedError, Equatable {
    case unusableResponse(String)

    public var errorDescription: String? {
        switch self {
        case .unusableResponse(let detail): return "Could not read the release feed: \(detail)."
        }
    }
}

/// Where new versions are announced. Injected so the check is testable offline.
public protocol ReleaseFeed: Sendable {
    func latestRelease() async throws -> AvailableUpdate
}

/// Dotted numeric version comparison. Deliberately conservative: anything it
/// cannot parse is treated as "no update", so a malformed feed can never nag
/// the user or claim a downgrade is newer.
public enum SemanticVersion {
    static func components(_ raw: String) -> [Int]? {
        var text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.hasPrefix("v") || text.hasPrefix("V") { text.removeFirst() }
        guard !text.isEmpty else { return nil }
        let parts = text.split(separator: ".", omittingEmptySubsequences: false)
        var numbers: [Int] = []
        for part in parts {
            guard let value = Int(part), value >= 0 else { return nil }
            numbers.append(value)
        }
        return numbers.isEmpty ? nil : numbers
    }

    public static func isNewer(_ candidate: String, than current: String) -> Bool {
        guard let lhs = components(candidate), let rhs = components(current) else { return false }
        for index in 0..<max(lhs.count, rhs.count) {
            // A missing component counts as zero, so "1.2" and "1.2.0" are equal.
            let left = index < lhs.count ? lhs[index] : 0
            let right = index < rhs.count ? rhs[index] : 0
            if left != right { return left > right }
        }
        return false
    }
}

/// Reads the newest published release from the GitHub releases API. No token,
/// no user data sent, and only the tag and page URL are read from the reply.
public struct GitHubReleaseFeed: ReleaseFeed {
    let url: URL
    let session: URLSession

    public init(url: URL, session: URLSession = .shared) {
        self.url = url
        self.session = session
    }

    static func parse(_ data: Data) throws -> AvailableUpdate {
        struct Response: Decodable {
            let tag_name: String
            let html_url: String
            let draft: Bool?
            let prerelease: Bool?
        }
        guard let parsed = try? JSONDecoder().decode(Response.self, from: data) else {
            throw UpdateCheckError.unusableResponse("unexpected format")
        }
        guard parsed.draft != true, parsed.prerelease != true else {
            throw UpdateCheckError.unusableResponse("latest release is a draft or prerelease")
        }
        guard let pageURL = URL(string: parsed.html_url) else {
            throw UpdateCheckError.unusableResponse("bad release URL")
        }
        var version = parsed.tag_name.trimmingCharacters(in: .whitespacesAndNewlines)
        if version.hasPrefix("v") || version.hasPrefix("V") { version.removeFirst() }
        return AvailableUpdate(version: version, url: pageURL)
    }

    public func latestRelease() async throws -> AvailableUpdate {
        var request = URLRequest(url: url)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.timeoutInterval = 15
        let (data, _) = try await session.data(for: request)
        return try Self.parse(data)
    }
}
