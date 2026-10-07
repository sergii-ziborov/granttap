import Foundation
import TweetNacl

struct AccountComputer: Decodable, Identifiable {
    let id: String
    let name: String
    let createdAt: Double
    let lastSeenAt: Double?
}

enum AccountRecovery {
    static func computers(session: GrantTapAccountSession,
                          transport: URLSession = .shared) async throws -> [AccountComputer] {
        var all: [AccountComputer] = []
        var cursor: String?
        var seenCursors = Set<String>()
        var seenMachines = Set<String>()
        for _ in 0..<100 {
            let path = "machines?pageSize=100" + (cursor.map { "&cursor=\($0)" } ?? "")
            let response = try await GrantTapAccountAPI.json(path, token: session.token,
                                                             transport: transport)
            guard let rows = response["machines"] as? [[String: Any]],
                  let data = try? JSONSerialization.data(withJSONObject: rows),
                  let page = try? JSONDecoder().decode([AccountComputer].self, from: data)
            else { throw AccountBridgeError.invalidResponse }
            for machine in page where seenMachines.insert(machine.id).inserted {
                all.append(machine)
            }
            guard let next = response["nextCursor"] as? String else { return all }
            guard !next.isEmpty, seenCursors.insert(next).inserted else {
                throw AccountBridgeError.invalidResponse
            }
            cursor = next
        }
        throw AccountBridgeError.invalidResponse
    }

    static func connect(_ computer: AccountComputer,
                        session: GrantTapAccountSession, transport: URLSession = .shared,
                        pollDelayNanoseconds: UInt64 = 2_000_000_000) async throws -> Pairing {
        let key = try NaclBox.keyPair()
        let request = try await GrantTapAccountAPI.json(
            "machines/\(computer.id)/requests", method: "POST",
            body: ["phonePublicKey": GrantTapAccountAPI.encodeURL(key.publicKey)],
            token: session.token, transport: transport)
        guard let id = request["id"] as? String, UUID(uuidString: id) != nil else {
            throw AccountBridgeError.invalidResponse
        }
        for _ in 0..<75 {
            try Task.checkCancellation()
            try await Task.sleep(nanoseconds: pollDelayNanoseconds)
            let result = try await GrantTapAccountAPI.json("requests/\(id)", token: session.token,
                                                           transport: transport)
            if (result["status"] as? String) == "pending" { continue }
            guard let encrypted = result["encryptedOffer"] as? String else {
                throw AccountBridgeError.invalidResponse
            }
            return try open(encrypted, requestId: id, machineId: computer.id,
                            secretKey: key.secretKey)
        }
        throw AccountBridgeError.expired
    }

    static func open(_ encrypted: String, requestId: String,
                     machineId: String, secretKey: Data) throws -> Pairing {
        struct Envelope: Decodable {
            let senderPublicKey: String
            let nonce: String
            let box: String
        }
        struct Offer: Decodable {
            let schema: String
            let requestId: String
            let machineId: String
            let pairing: Pairing
        }
        guard encrypted.utf8.count <= 8192,
              let envelope = try? JSONDecoder().decode(Envelope.self, from: Data(encrypted.utf8)),
              Pairing.isValidKey(envelope.senderPublicKey),
              let data = Crypto.open(nonceB64: envelope.nonce, boxB64: envelope.box,
                                     theirPublicKeyB64: envelope.senderPublicKey,
                                     mySecretKeyB64: secretKey.base64EncodedString()),
              let offer = try? JSONDecoder().decode(Offer.self, from: data),
              offer.schema == "granttap.account-offer.v1",
              offer.requestId == requestId, offer.machineId == machineId,
              Pairing.isValid(offer.pairing) else {
            throw AccountBridgeError.invalidResponse
        }
        return offer.pairing
    }
}
