import CryptoKit
import Foundation

enum ProjectNetworkConfigurationHTTP {
    struct Body: Codable {
        let issuerKeyId: String
        let expiresAt: Double
        let envelope: Envelope
    }

    static func identifier(projectId: String, endpointId: String) throws -> String {
        let bytes = try JSONSerialization.data(withJSONObject:
            ["granttap-project-transport-v1", projectId, endpointId], options: [.withoutEscapingSlashes])
        return SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined()
    }

    static func prepare(_ command: ProjectTransportCommand, pairing: Pairing) throws -> Body {
        guard !pairing.isHub, pairing.role == "phone",
              let issuer = CiphertextRecipient.identifier(publicKey: pairing.myPublicKey),
              let recipient = CiphertextRecipient.identifier(publicKey: pairing.peerPublicKey) else {
            throw ProjectNetworkError.invalidScope
        }
        let plain = try RelayClient.encodeOmittingNulls(command)
        guard plain.count <= 60_000 else { throw ProjectNetworkError.invalidScope }
        let seal = try Crypto.seal(plain, theirPublicKeyB64: pairing.peerPublicKey, mySecretKeyB64: pairing.mySecretKey)
        return Body(issuerKeyId: issuer, expiresAt: command.expiresAt,
            envelope: Envelope(room: pairing.room, from: .phone, to: "machine", senderId: pairing.senderId,
                recipientKeyId: recipient, deliveryId: try identifier(projectId: command.projectId,
                    endpointId: command.targetEndpointId), wake: nil, expiresAt: command.expiresAt,
                nonce: seal.nonce, box: seal.box))
    }

    static func publish(_ command: ProjectTransportCommand, pairing: Pairing) async throws {
        let body = try prepare(command, pairing: pairing)
        guard let credential = pairing.pushAuth, !credential.isEmpty,
              Pairing.isAllowedSocketRelay(pairing.relayUrl),
              var address = URLComponents(string: pairing.relayUrl), let id = body.envelope.deliveryId else {
            throw ProjectNetworkError.invalidScope
        }
        address.scheme = address.scheme == "wss" ? "https" : "http"
        address.path = "/task-job-configurations/\(id)"
        address.queryItems = [URLQueryItem(name: "room", value: pairing.room)]
        guard let url = address.url else { throw ProjectNetworkError.invalidScope }
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 20)
        request.httpMethod = "PUT"
        request.httpBody = try JSONEncoder().encode(body)
        request.setValue("Bearer \(credential)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let (data, response) = try await fetch(request)
        struct Response: Decodable {
            struct Configuration: Decodable { let id: String; let issuerKeyId: String; let expiresAt: Double; let envelope: Envelope }
            let configuration: Configuration
        }
        guard let http = response as? HTTPURLResponse, [200, 201].contains(http.statusCode),
              let accepted = try? JSONDecoder().decode(Response.self, from: data), accepted.configuration.id == id,
              accepted.configuration.issuerKeyId == body.issuerKeyId, accepted.configuration.expiresAt == body.expiresAt,
              accepted.configuration.envelope.nonce == body.envelope.nonce,
              accepted.configuration.envelope.box == body.envelope.box else { throw ProjectNetworkError.relayUnavailable }
    }

    private static func fetch(_ request: URLRequest) async throws -> (Data, URLResponse) {
        let session = URLSession(configuration: .ephemeral, delegate: ConfigurationRedirectPolicy(), delegateQueue: nil)
        defer { session.invalidateAndCancel() }
        let (bytes, response) = try await session.bytes(for: request)
        var data = Data()
        for try await byte in bytes {
            guard data.count < 100_000 else { throw URLError(.dataLengthExceedsMaximum) }
            data.append(byte)
        }
        return (data, response)
    }
}

private final class ConfigurationRedirectPolicy: NSObject, URLSessionTaskDelegate {
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) { completionHandler(nil) }
}
