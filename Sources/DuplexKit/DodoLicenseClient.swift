import Foundation

/// Dodo Payments' public license endpoints (no API secret involved):
/// POST /licenses/activate    {license_key, name}                     -> 2xx {id, ...}
/// POST /licenses/validate    {license_key, license_key_instance_id?} -> 200 {valid}
/// POST /licenses/deactivate  {license_key, license_key_instance_id}  -> 200
///
/// Explicit key verdicts arrive as HTTP statuses (403 inactive, 404 unknown,
/// 422 activation limit) and map to `.keyInvalid`; everything ambiguous maps
/// to `.network` so it can never downgrade license state.
public struct DodoLicenseClient: LicenseClient {
    public static let liveBase = URL(string: "https://live.dodopayments.com/licenses")!
    public static let testBase = URL(string: "https://test.dodopayments.com/licenses")!

    let base: URL
    let transport: HTTPTransport

    public init(base: URL = DodoLicenseClient.liveBase,
                transport: HTTPTransport = URLSessionTransport()) {
        self.base = base
        self.transport = transport
    }

    public func activate(key: String, instanceName: String) async throws -> LicenseActivation {
        let (data, status) = try await post("activate", ["license_key": key, "name": instanceName])
        if (200..<300).contains(status) {
            struct Response: Decodable { let id: String }
            guard let parsed = try? JSONDecoder().decode(Response.self, from: data) else {
                throw LicenseClientError.network("activation response missing instance id (HTTP \(status))")
            }
            return LicenseActivation(activationID: parsed.id)
        }
        throw explicitRejection(status: status, data: data,
                                fallback: "The license key was not accepted (HTTP \(status)).")
    }

    public func validate(key: String, activationID: String?) async throws -> Bool {
        var body = ["license_key": key]
        if let activationID { body["license_key_instance_id"] = activationID }
        let (data, status) = try await post("validate", body)
        struct Response: Decodable { let valid: Bool }
        guard status == 200, let parsed = try? JSONDecoder().decode(Response.self, from: data) else {
            // Anything but an explicit 200 {valid} is ambiguity, never revocation.
            throw LicenseClientError.network("unexpected validate response (HTTP \(status))")
        }
        return parsed.valid
    }

    public func deactivate(key: String, activationID: String) async throws {
        let (data, status) = try await post(
            "deactivate", ["license_key": key, "license_key_instance_id": activationID])
        if (200..<300).contains(status) { return }
        throw explicitRejection(status: status, data: data,
                                fallback: "Could not deactivate (HTTP \(status)).")
    }

    /// 403/404/422 are the server explicitly rejecting the key or activation;
    /// everything else is treated as a transport-level ambiguity.
    private func explicitRejection(status: Int, data: Data, fallback: String) -> LicenseClientError {
        let serverMessage: String? = {
            struct ErrorBody: Decodable { let message: String?; let error: String? }
            let parsed = try? JSONDecoder().decode(ErrorBody.self, from: data)
            return parsed?.message ?? parsed?.error
        }()
        switch status {
        case 403: return .keyInvalid(serverMessage ?? "This license key is inactive.")
        case 404: return .keyInvalid(serverMessage ?? "License key not found.")
        case 422: return .keyInvalid(serverMessage ?? "Activation limit reached.")
        default: return .network(serverMessage ?? fallback)
        }
    }

    private func post(_ path: String, _ body: [String: String]) async throws -> (Data, Int) {
        do {
            return try await transport.postJSON(url: base.appendingPathComponent(path), json: body)
        } catch let error as LicenseClientError {
            throw error
        } catch {
            throw LicenseClientError.network(error.localizedDescription)
        }
    }
}
