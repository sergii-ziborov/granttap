import Foundation

extension Pairing {
    typealias PairingDataLoader = (URL) async throws -> (Data, URLResponse)

    /// Fetch a pairing from a relay-visible random mailbox. Its independent
    /// 256-bit key stays in the QR/manual token and is never sent to the relay.
    static func fetchSecurePairing(relayBase: String, mailboxId: String,
                                   transferKey: String,
                                   dataLoader: @escaping PairingDataLoader = {
                                       try await URLSession.shared.data(from: $0)
                                   }) async -> Result<Pairing, PairingError> {
        struct Blob: Decodable { let nonce: String; let box: String }

        guard let base = normalizedPairingHTTPBase(relayBase) else {
            return .failure(.badCode)
        }

        let mailbox = mailboxId.lowercased()
        guard mailbox.count == mailboxLength,
              mailbox.allSatisfy({ $0.isHexDigit }),
              Crypto.isValidTransferKey(transferKey),
              let url = URL(string: "\(base)/pair/\(mailbox)") else {
            return .failure(.badCode)
        }

        do {
            let (data, response) = try await dataLoader(url)
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            guard status == 200 else {
                return .failure(.forHTTPStatus(status))
            }
            guard let blob = try? JSONDecoder().decode(Blob.self, from: data),
                  let plain = Crypto.openWithTransferKey(nonceB64: blob.nonce, boxB64: blob.box,
                                                         key: transferKey),
                  let decoded = try? JSONDecoder().decode(Pairing.self, from: plain) else {
                return .failure(.badCode)
            }
            let pairing = decoded.migratingRetiredRelay()
            guard isValid(pairing) else { return .failure(.badCode) }
            return .success(pairing)
        } catch {
            return .failure(.unreachable)
        }
    }

    /// The hosts the app's `NSAllowsLocalNetworking` ATS exception covers, and so
    /// the only ones a scheme-less address may fall back to plaintext http for:
    /// `.local` names, localhost, and RFC1918 / loopback literals.
    static func isLocalNetworkHost(_ authority: String) -> Bool {
        var host = authority
        if let end = host.firstIndex(where: { $0 == "/" || $0 == "?" || $0 == "#" }) {
            host = String(host[..<end])
        }
        if let at = host.lastIndex(of: "@") {           // drop any user info
            host = String(host[host.index(after: at)...])
        }
        if host.hasPrefix("[") {                        // IPv6 literal, e.g. [::1]:8787
            guard let close = host.firstIndex(of: "]") else { return false }
            return host[host.index(after: host.startIndex)..<close] == "::1"
        }
        if host == "::1" { return true }
        if let colon = host.lastIndex(of: ":") {        // drop the port
            host = String(host[..<colon])
        }
        host = host.lowercased()

        if host == "localhost" || host.hasSuffix(".localhost") || host.hasSuffix(".local") {
            return true
        }
        // A single-label name has no public DNS meaning — `macbook:8787` can only
        // be a LAN host, so it keeps the plaintext fallback.
        if !host.isEmpty, !host.contains(".") { return true }

        let parts = host.split(separator: ".", omittingEmptySubsequences: false)
        let octets = parts.compactMap { UInt8($0) }
        guard parts.count == 4, octets.count == 4 else { return false }
        switch (octets[0], octets[1]) {
        case (127, _), (10, _), (192, 168), (172, 16...31): return true
        default: return false
        }
    }

    /// Production relays must be authenticated with TLS. Plain WebSocket is
    /// retained solely for a helper running on localhost or the local network.
    static func isAllowedSocketRelay(_ rawValue: String) -> Bool {
        let value = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let components = URLComponents(string: value),
              let scheme = components.scheme?.lowercased(),
              let host = components.host, !host.isEmpty,
              components.user == nil, components.password == nil,
              components.query == nil, components.fragment == nil,
              components.path.isEmpty || components.path == "/" else { return false }
        if scheme == "wss" { return true }
        return scheme == "ws" && isLocalNetworkHost(host)
    }

    static func normalizedPairingHTTPBase(_ rawValue: String) -> String? {
        var value = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return nil }
        if !value.contains("://") {
            value = (isLocalNetworkHost(value) ? "http://" : "https://") + value
        }
        guard var components = URLComponents(string: value),
              let scheme = components.scheme?.lowercased(),
              let host = components.host, !host.isEmpty,
              components.user == nil, components.password == nil,
              components.query == nil, components.fragment == nil,
              components.path.isEmpty || components.path == "/" else { return nil }
        switch scheme {
        case "wss":
            components.scheme = "https"
        case "ws":
            guard isLocalNetworkHost(host) else { return nil }
            components.scheme = "http"
        case "https":
            break
        case "http":
            guard isLocalNetworkHost(host) else { return nil }
        default:
            return nil
        }
        components.path = ""
        guard let url = components.url else { return nil }
        return url.absoluteString.replacingOccurrences(of: "/$", with: "",
                                                       options: .regularExpression)
    }

    static func isValidKey(_ value: String) -> Bool {
        guard let decoded = Data(base64Encoded: value), decoded.count == 32 else { return false }
        return decoded.base64EncodedString() == value
    }

    static func isValid(_ pairing: Pairing) -> Bool {
        guard pairing.role == "phone",
              isAllowedSocketRelay(pairing.relayUrl),
              (16...64).contains(pairing.room.count),
              pairing.room == pairing.room.lowercased(),
              pairing.room.allSatisfy({ $0.isHexDigit }),
              !pairing.senderId.isEmpty, pairing.senderId.count <= 180,
              !pairing.deviceName.isEmpty, pairing.deviceName.count <= 180,
              isValidKey(pairing.myPublicKey),
              isValidKey(pairing.mySecretKey),
              isValidKey(pairing.peerPublicKey) else { return false }
        if let extras = pairing.extraPeerPublicKeys {
            guard extras.count <= 16, extras.allSatisfy(isValidKey) else { return false }
        }
        if let pushAuth = pairing.pushAuth {
            return pushAuth.count == 64 && pushAuth == pushAuth.lowercased()
                && pushAuth.allSatisfy({ $0.isHexDigit })
        }
        return true
    }

    /// Alias used by the multi-connection store.
    static func isValidPublic(_ pairing: Pairing) -> Bool { isValid(pairing) }
}
