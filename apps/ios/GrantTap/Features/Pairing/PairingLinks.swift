import Foundation

extension Pairing {
    /// Parse the protocol-v2 QR returned by the MCP `connect` tool:
    /// `granttap://pair-v2?v=2&u=<relay>&m=<mailbox>&k=<256-bit-key>`
    /// (also accepts `granttap://pair?v=2&...` from older scanners/hosts).
    /// Only `m` reaches the relay; `k` is used locally after retrieval.
    static func secureLink(fromURI text: String) -> SecureLink? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let comps = URLComponents(string: trimmed),
              comps.scheme == "granttap" || comps.scheme == "nodvox" else { return nil }

        var q: [String: String] = [:]
        comps.queryItems?.forEach { if let value = $0.value { q[$0.name] = value } }
        let host = comps.host?.lowercased()
        let isV2Host = host == "pair-v2" || (host == "pair" && q["v"] == "2")
        guard isV2Host else { return nil }

        guard let relay = q["u"], !relay.isEmpty,
              q["v"] == "2",
              let mailbox = q["m"]?.lowercased(), mailbox.count == mailboxLength,
              mailbox.allSatisfy({ $0.isHexDigit }),
              let key = q["k"], Crypto.isValidTransferKey(key) else { return nil }
        return SecureLink(
            relayBase: migratedRelayURL(relay), mailboxId: mailbox, transferKey: key
        )
    }

    /// Manual fallback for Simulator/accessibility: `<mailbox>.<transfer-key>`.
    static func secureLink(relayBase: String, manualToken: String) -> SecureLink? {
        let pieces = manualToken.trimmingCharacters(in: .whitespacesAndNewlines)
            .split(separator: ".", maxSplits: 1, omittingEmptySubsequences: false)
        guard pieces.count == 2 else { return nil }
        let mailbox = String(pieces[0]).lowercased()
        let key = String(pieces[1])
        guard mailbox.count == mailboxLength,
              mailbox.allSatisfy({ $0.isHexDigit }),
              Crypto.isValidTransferKey(key) else { return nil }
        return SecureLink(
            relayBase: migratedRelayURL(relayBase), mailboxId: mailbox, transferKey: key
        )
    }

    /// Parse the legacy full-secret QR payload:
    /// `granttap://pair?v=1&u=<relay>&r=<room>&s=<secret>&p=<peerPub>&k=<myPub>&i=<id>`
    /// Keys are base64url so they survive the query string.
    /// Note: protocol-v2 mailbox links use `secureLink(fromURI:)` / `pair-v2`, not this.
    static func fromURI(_ text: String) -> Pairing? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let comps = URLComponents(string: trimmed),
              comps.scheme == "granttap" || comps.scheme == "nodvox" else { return nil }

        var q: [String: String] = [:]
        comps.queryItems?.forEach { if let v = $0.value { q[$0.name] = v } }

        // v2 mailbox links must not be misread as incomplete v1 payloads.
        let host = comps.host?.lowercased()
        if host == "pair-v2" || q["v"] == "2" { return nil }
        guard host == nil || host == "pair" else { return nil }

        func unb64url(_ s: String) -> String {
            var t = s.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
            t += String(repeating: "=", count: (4 - t.count % 4) % 4)
            return t
        }

        guard let rawRelay = q["u"], !rawRelay.isEmpty else { return nil }
        let relay = migratedRelayURL(rawRelay)
        guard isAllowedSocketRelay(relay),
              let room = q["r"], !room.isEmpty,
              let secret = q["s"], !secret.isEmpty,
              let peer = q["p"], !peer.isEmpty else { return nil }

        let pairing = Pairing(
            relayUrl: relay,
            room: room,
            role: "phone",
            deviceName: "iPhone",
            senderId: q["i"] ?? "phone",
            myPublicKey: unb64url(q["k"] ?? ""),
            mySecretKey: unb64url(secret),
            peerPublicKey: unb64url(peer),
            pushAuth: q["a"]
        )
        return isValid(pairing) ? pairing : nil
    }

    /// Read the pre-multi-connection single Keychain slot (migration only).
    static func loadLegacySingle() -> Pairing? {
        if let data = KeychainPairing.load(service: keychainService),
           let decoded = try? JSONDecoder().decode(Pairing.self, from: data) {
            let pairing = decoded.migratingRetiredRelay()
            guard isValid(pairing) else { return nil }
            return pairing
        }
        guard let legacy = UserDefaults.standard.data(forKey: storeKey),
              let decoded = try? JSONDecoder().decode(Pairing.self, from: legacy) else {
            return nil
        }
        let pairing = decoded.migratingRetiredRelay()
        guard isValid(pairing) else { return nil }
        return pairing
    }

    static func removeLegacySingleOnly() {
        KeychainPairing.remove(service: keychainService)
        UserDefaults.standard.removeObject(forKey: storeKey)
    }
}
