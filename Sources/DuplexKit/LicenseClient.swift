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
}

public struct URLSessionTransport: HTTPTransport {
    public init() {}
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

/// Lemon Squeezy's public license endpoints. Per-key, no API secret involved.
public struct LemonSqueezyClient: LicenseClient {
    static let base = URL(string: "https://api.lemonsqueezy.com/v1/licenses")!
    let transport: HTTPTransport

    public init(transport: HTTPTransport = URLSessionTransport()) { self.transport = transport }

    public func activate(key: String, instanceName: String) async throws -> LicenseActivation {
        let (data, status) = try await post("activate", ["license_key": key, "instance_name": instanceName])
        struct Response: Decodable {
            let activated: Bool
            let error: String?
            let instance: Inst?
            struct Inst: Decodable { let id: String }
        }
        guard let parsed = try? JSONDecoder().decode(Response.self, from: data) else {
            throw LicenseClientError.network("unexpected response (HTTP \(status))")
        }
        guard parsed.activated, let id = parsed.instance?.id else {
            throw LicenseClientError.keyInvalid(parsed.error ?? "The license key was not accepted.")
        }
        return LicenseActivation(activationID: id)
    }

    public func validate(key: String, activationID: String?) async throws -> Bool {
        var form = ["license_key": key]
        if let activationID { form["instance_id"] = activationID }
        let (data, status) = try await post("validate", form)
        struct Response: Decodable { let valid: Bool }
        guard let parsed = try? JSONDecoder().decode(Response.self, from: data) else {
            throw LicenseClientError.network("unexpected response (HTTP \(status))")
        }
        return parsed.valid
    }

    public func deactivate(key: String, activationID: String) async throws {
        let (data, status) = try await post("deactivate", ["license_key": key, "instance_id": activationID])
        struct Response: Decodable { let deactivated: Bool }
        guard let parsed = try? JSONDecoder().decode(Response.self, from: data), parsed.deactivated else {
            throw LicenseClientError.network("could not deactivate (HTTP \(status))")
        }
    }

    private func post(_ path: String, _ form: [String: String]) async throws -> (Data, Int) {
        do {
            return try await transport.post(url: Self.base.appendingPathComponent(path), form: form)
        } catch let error as LicenseClientError {
            throw error
        } catch {
            throw LicenseClientError.network(error.localizedDescription)
        }
    }
}
