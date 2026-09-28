import CryptoKit
import Foundation

enum DeviceEndpointDirectory {
    typealias Loader = (URLRequest) async throws -> (Data, URLResponse)
    struct Record: Decodable { let nonce: String; let box: String; let expiresAt: Double }
    struct Endpoint: Decodable {
        let schema: String; let room: String; let relayUrl: String; let expiresAt: Double
    }

    static func isManaged(_ address: String) -> Bool {
        URLComponents(string: address)?.host?.lowercased() == "relay.granttap.com"
    }

    static func resolve(pairing: Pairing, allowsManaged: Bool, now: Date = Date(),
                        loader: @escaping Loader = boundedFetch) async -> String? {
        let directory = pairing.directoryUrl ?? (isManaged(pairing.relayUrl) ? pairing.relayUrl : nil)
        guard let directory else { return Pairing.isAllowedSocketRelay(pairing.relayUrl) ? pairing.relayUrl : nil }
        if pairing.directoryUrl == nil && allowsManaged { return pairing.relayUrl }
        guard let request = lookupRequest(pairing: pairing, directory: directory) else { return nil }
        do {
            let (data, response) = try await loader(request)
            guard (response as? HTTPURLResponse)?.statusCode == 200, data.count <= 12_000,
                  let record = try? JSONDecoder().decode(Record.self, from: data),
                  record.expiresAt > now.timeIntervalSince1970 * 1_000,
                  record.expiresAt <= now.timeIntervalSince1970 * 1_000 + 900_000,
                  Data(base64Encoded: record.nonce)?.count == 24,
                  let box = Data(base64Encoded: record.box), (16...8_192).contains(box.count),
                  let plain = Crypto.open(nonceB64: record.nonce, boxB64: record.box,
                    theirPublicKeyB64: pairing.peerPublicKey, mySecretKeyB64: pairing.mySecretKey),
                  let endpoint = try? JSONDecoder().decode(Endpoint.self, from: plain),
                  endpoint.schema == "granttap.direct-endpoint.v1", endpoint.room == pairing.room,
                  endpoint.expiresAt == record.expiresAt,
                  Pairing.isAllowedSocketRelay(endpoint.relayUrl), !isManaged(endpoint.relayUrl) else { return nil }
            return endpoint.relayUrl
        } catch { return nil }
    }

    static func lookupRequest(pairing: Pairing, directory: String) -> URLRequest? {
        guard Pairing.isAllowedSocketRelay(directory), let credential = pairing.pushAuth,
              var url = URLComponents(string: directory) else { return nil }
        url.scheme = url.scheme == "wss" ? "https" : "http"
        url.path = "/endpoint"
        let recipient = SHA256.hash(data: Data("\(pairing.myPublicKey):\(pairing.peerPublicKey)".utf8))
            .map { String(format: "%02x", $0) }.joined()
        url.queryItems = [URLQueryItem(name: "room", value: pairing.room),
                          URLQueryItem(name: "recipient", value: recipient)]
        guard let address = url.url else { return nil }
        var request = URLRequest(url: address)
        request.timeoutInterval = 10
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.setValue("Bearer \(credential)", forHTTPHeaderField: "Authorization")
        return request
    }

    static func boundedFetch(_ request: URLRequest) async throws -> (Data, URLResponse) {
        let session = URLSession(configuration: .ephemeral, delegate: EndpointRedirectPolicy(), delegateQueue: nil)
        defer { session.invalidateAndCancel() }
        let (bytes, response) = try await session.bytes(for: request)
        var data = Data()
        for try await byte in bytes {
            guard data.count < 12_000 else { throw URLError(.dataLengthExceedsMaximum) }
            data.append(byte)
        }
        return (data, response)
    }
}

private final class EndpointRedirectPolicy: NSObject, URLSessionTaskDelegate {
    func urlSession(_ session: URLSession, task: URLSessionTask,
                    willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
        completionHandler(nil)
    }
}
