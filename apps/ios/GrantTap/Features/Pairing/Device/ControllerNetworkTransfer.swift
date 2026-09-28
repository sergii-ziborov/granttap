import Foundation

struct ControllerPairRequest: Codable {
    let type = "controller.pair.request"
    let requestId: String
    let createdAt: Double

    enum CodingKeys: String, CodingKey { case type, requestId, createdAt }
}

struct ControllerPairOffer: Codable {
    let type: String
    let requestId: String
    let room: String
    let status: String
    let uri: String?
    let expiresAt: Double?
    let reason: String?
    let createdAt: Double
}

enum ControllerNetworkTransfer {
    struct Bundle: Codable {
        let v: Int
        let links: [String]
    }

    enum TransferError: Error {
        case invalidCode, unavailable, expired, incomplete
    }

    typealias Loader = (URL) async throws -> (Data, URLResponse)
    typealias Uploader = (URL, Data) async throws -> (Data, URLResponse)

    static func bundleLink(from uri: String) -> Pairing.SecureLink? {
        guard let components = URLComponents(string: uri),
              components.scheme == "granttap", components.host == "controllers",
              let query = components.queryItems else { return nil }
        let values = Dictionary(query.compactMap { item -> (String, String)? in
            guard let value = item.value else { return nil }
            return (item.name, value)
        }, uniquingKeysWith: { first, _ in first })
        guard values["v"] == "1", let relay = values["u"],
              let mailbox = values["m"], let key = values["k"],
              mailbox.count == Pairing.mailboxLength,
              mailbox.allSatisfy({ $0.isHexDigit }), Crypto.isValidTransferKey(key),
              Pairing.normalizedPairingHTTPBase(relay) != nil else { return nil }
        return Pairing.SecureLink(relayBase: relay, mailboxId: mailbox, transferKey: key)
    }

    static func publish(
        uris: [String], relay: String,
        uploader: @escaping Uploader = { url, body in
            var request = URLRequest(url: url)
            request.httpMethod = "PUT"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = body
            return try await URLSession.shared.data(for: request)
        }
    ) async throws -> String {
        guard (1...16).contains(uris.count),
              uris.allSatisfy({ Pairing.secureLink(fromURI: $0) != nil }),
              let base = Pairing.normalizedPairingHTTPBase(relay) else {
            throw TransferError.invalidCode
        }
        let bytes = try Crypto.randomBytes(32)
        let key = bytes.base64EncodedString().replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "")
        let mailbox = try Crypto.randomBytes(16).map { String(format: "%02x", $0) }.joined()
        guard let plain = try? JSONEncoder().encode(Bundle(v: 1, links: uris)),
              let sealed = Crypto.openableSeal(plain, key: key),
              let body = try? JSONEncoder().encode(sealed),
              let url = URL(string: "\(base)/pair/\(mailbox)") else {
            throw TransferError.invalidCode
        }
        let (_, response) = try await uploader(url, body)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else {
            throw TransferError.unavailable
        }
        var code = URLComponents()
        code.scheme = "granttap"
        code.host = "controllers"
        code.queryItems = [URLQueryItem(name: "v", value: "1"),
                           URLQueryItem(name: "u", value: base),
                           URLQueryItem(name: "m", value: mailbox),
                           URLQueryItem(name: "k", value: key)]
        guard let result = code.url?.absoluteString else { throw TransferError.invalidCode }
        return result
    }

    static func fetch(
        _ link: Pairing.SecureLink,
        loader: @escaping Loader = { try await URLSession.shared.data(from: $0) },
        pairingFetcher: @escaping (Pairing.SecureLink) async -> Result<Pairing, PairingError> = {
            await Pairing.fetchSecurePairing(relayBase: $0.relayBase,
                                             mailboxId: $0.mailboxId, transferKey: $0.transferKey)
        }
    ) async throws -> [Pairing] {
        guard let base = Pairing.normalizedPairingHTTPBase(link.relayBase),
              let url = URL(string: "\(base)/pair/\(link.mailboxId)") else {
            throw TransferError.invalidCode
        }
        let (data, response) = try await loader(url)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw TransferError.expired }
        let blob = try? JSONDecoder().decode(Crypto.SealResult.self, from: data)
        guard let blob, let plain = Crypto.openWithTransferKey(
            nonceB64: blob.nonce, boxB64: blob.box, key: link.transferKey
        ), let bundle = try? JSONDecoder().decode(Bundle.self, from: plain),
              bundle.v == 1, (1...16).contains(bundle.links.count) else {
            throw TransferError.invalidCode
        }
        var pairings: [Pairing] = []
        var rooms = Set<String>()
        for uri in bundle.links {
            guard let item = Pairing.secureLink(fromURI: uri) else { throw TransferError.invalidCode }
            let result = await pairingFetcher(item)
            guard case .success(let pairing) = result, Pairing.isValid(pairing),
                  rooms.insert(pairing.room).inserted else { throw TransferError.incomplete }
            pairings.append(pairing)
        }
        return pairings
    }
}
