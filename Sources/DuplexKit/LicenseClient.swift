import Foundation

public struct LicenseActivation: Equatable, Sendable {
    public let activationID: String
    public init(activationID: String) { self.activationID = activationID }
}

public enum LicenseClientError: Error, LocalizedError, Equatable {
    /// The server explicitly rejected the key (bad key, disabled, limit reached).
    case keyInvalid(String)
    /// Transport-level failure or unparseable response. Never downgrades license state.
    case network(String)

    public var errorDescription: String? {
        switch self {
        case .keyInvalid(let message): return message
        case .network(let message): return "Could not reach the license server: \(message)"
        }
    }
}

public protocol LicenseClient: Sendable {
    func activate(key: String, instanceName: String) async throws -> LicenseActivation
    /// Returns false when the server explicitly reports the key invalid/revoked.
    /// Throws `.network` on transport failure (callers must NOT treat that as revocation).
    func validate(key: String, activationID: String?) async throws -> Bool
    func deactivate(key: String, activationID: String) async throws
}

public protocol HTTPTransport: Sendable {
    /// Form-encoded POST; returns (body, HTTP status).
    func post(url: URL, form: [String: String]) async throws -> (Data, Int)
    /// JSON POST; returns (body, HTTP status).
    func postJSON(url: URL, json: [String: String]) async throws -> (Data, Int)
}

public struct URLSessionTransport: HTTPTransport {
    public init() {}

    public func postJSON(url: URL, json: [String: String]) async throws -> (Data, Int) {
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.httpBody = try JSONEncoder().encode(json)
        let (data, response) = try await URLSession.shared.data(for: request)
        return (data, (response as? HTTPURLResponse)?.statusCode ?? 0)
    }

    public func post(url: URL, form: [String: String]) async throws -> (Data, Int) {
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~")
        request.httpBody = form
            .map { "\($0.key)=\($0.value.addingPercentEncoding(withAllowedCharacters: allowed) ?? "")" }
            .joined(separator: "&")
            .data(using: .utf8)
        let (data, response) = try await URLSession.shared.data(for: request)
        return (data, (response as? HTTPURLResponse)?.statusCode ?? 0)
    }
}
