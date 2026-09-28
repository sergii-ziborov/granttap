import Foundation
import Security

/// Phone-side multi-computer registry. Relay rooms stay 1:1; the iPhone holds
/// many rooms and may open a WebSocket per room. Pair/scan adds; replace-all
/// is explicit. Mirrors `packages/core/paired-connections.ts`.

struct LinkedComputer: Codable, Equatable, Identifiable {
    var id: String
    var pairing: Pairing
    var label: String
    var addedAt: Double
    var lastCatalogAt: Double
    var lastMachineName: String

    var displayName: String {
        // "phone" is the role a pairing was minted with, not a name — and the
        // label is copied from the pairing's device name at pairing time, so
        // it can carry the same word.
        let custom = Self.nameOrNothing(label)
        if !custom.isEmpty { return custom }
        let device = Self.nameOrNothing(pairing.deviceName)
        if !device.isEmpty { return device }
        let machine = lastMachineName.trimmingCharacters(in: .whitespacesAndNewlines)
        if !machine.isEmpty { return machine }
        let short = id.prefix(8)
        return "PC \(short)"
    }

    static func nameOrNothing(_ value: String) -> String {
        let clean = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return ["phone", "machine"].contains(clean.lowercased()) ? "" : clean
    }
}

struct ConnectionRegistry: Codable, Equatable {
    var connections: [LinkedComputer]
    var preferredId: String?

    static let empty = ConnectionRegistry(connections: [], preferredId: nil)

    var preferred: LinkedComputer? {
        if let preferredId, let hit = connections.first(where: { $0.id == preferredId }) {
            return hit
        }
        return connections.first
    }
}

enum PairAddMode: String {
    case add
    case replaceAll = "replace-all"
}

enum ConnectionRegistryLogic {
    static func upsert(
        _ reg: ConnectionRegistry,
        pairing: Pairing,
        mode: PairAddMode = .add,
        label: String? = nil,
        prefer: Bool = true,
        now: Double = Date().timeIntervalSince1970 * 1000
    ) -> ConnectionRegistry {
        let room = pairing.room
        let resolvedLabel = (label ?? pairing.deviceName)
            .trimmingCharacters(in: .whitespacesAndNewlines)

        if mode == .replaceAll {
            let next = LinkedComputer(
                id: room,
                pairing: pairing,
                label: resolvedLabel,
                addedAt: now,
                lastCatalogAt: 0,
                lastMachineName: ""
            )
            return ConnectionRegistry(connections: [next], preferredId: room)
        }

        var connections = reg.connections
        if let idx = connections.firstIndex(where: { $0.id == room }) {
            let existing = connections[idx]
            let samePeer = existing.pairing.peerPublicKey == pairing.peerPublicKey
            connections[idx] = LinkedComputer(
                id: room,
                pairing: pairing,
                label: resolvedLabel.isEmpty ? existing.label : resolvedLabel,
                addedAt: existing.addedAt,
                lastCatalogAt: samePeer ? existing.lastCatalogAt : 0,
                lastMachineName: samePeer ? existing.lastMachineName : ""
            )
        } else {
            connections.append(LinkedComputer(
                id: room,
                pairing: pairing,
                label: resolvedLabel,
                addedAt: now,
                lastCatalogAt: 0,
                lastMachineName: ""
            ))
        }

        var preferredId = reg.preferredId
        if prefer || preferredId == nil
            || !connections.contains(where: { $0.id == preferredId }) {
            preferredId = room
        }
        return ConnectionRegistry(connections: connections, preferredId: preferredId)
    }

    static func remove(_ reg: ConnectionRegistry, roomId: String) -> ConnectionRegistry {
        let connections = reg.connections.filter { $0.id != roomId }
        var preferredId = reg.preferredId
        if preferredId == roomId {
            preferredId = connections.first?.id
        }
        return ConnectionRegistry(connections: connections, preferredId: preferredId)
    }

    static func setPreferred(_ reg: ConnectionRegistry, roomId: String) -> ConnectionRegistry? {
        guard connectionsContain(reg, roomId) else { return nil }
        return ConnectionRegistry(connections: reg.connections, preferredId: roomId)
    }

    static func noteCatalog(
        _ reg: ConnectionRegistry,
        roomId: String,
        generatedAt: Double,
        machineName: String
    ) -> ConnectionRegistry {
        guard connectionsContain(reg, roomId) else { return reg }
        let connections = reg.connections.map { c -> LinkedComputer in
            guard c.id == roomId else { return c }
            var next = c
            next.lastCatalogAt = generatedAt
            if !machineName.isEmpty { next.lastMachineName = machineName }
            return next
        }
        return ConnectionRegistry(connections: connections, preferredId: reg.preferredId)
    }

    private static func connectionsContain(_ reg: ConnectionRegistry, _ roomId: String) -> Bool {
        reg.connections.contains(where: { $0.id == roomId })
    }
}

/// Keychain-backed multi-connection store. Migrates legacy single `Pairing`.
enum PairedConnectionStore {
    private static let keychainService = "com.ziborov.granttap.connections"
    private static let account = "linked-computers"

    static func load() -> ConnectionRegistry {
        if let data = KeychainBlob.load(service: keychainService, account: account),
           let reg = decodeRegistry(data), !reg.connections.isEmpty {
            let migrated = migratingRetiredRelays(in: reg)
            if migrated != reg { _ = save(migrated) }
            return migrated
        }
        // Migrate single-pairing Keychain / UserDefaults once.
        if let legacy = Pairing.loadLegacySingle(),
           Pairing.isValidPublic(legacy) {
            let reg = ConnectionRegistryLogic.upsert(
                .empty, pairing: legacy, mode: .add, prefer: true
            )
            _ = save(reg)
            Pairing.removeLegacySingleOnly()
            return reg
        }
        return .empty
    }

    @discardableResult
    static func save(_ reg: ConnectionRegistry) -> Bool {
        let migrated = migratingRetiredRelays(in: reg)
        let payload = RegistryFile(
            v: 1, preferredId: migrated.preferredId, connections: migrated.connections
        )
        guard let data = try? JSONEncoder().encode(payload) else { return false }
        return KeychainBlob.save(data, service: keychainService, account: account)
    }

    static func removeAll() {
        for conn in load().connections {
            SessionKeyVault.remove(room: conn.id)
        }
        KeychainBlob.remove(service: keychainService, account: account)
        Pairing.removeLegacySingleOnly()
    }

    private struct RegistryFile: Codable {
        var v: Int
        var preferredId: String?
        var connections: [LinkedComputer]
    }

    private static func migratingRetiredRelays(in reg: ConnectionRegistry) -> ConnectionRegistry {
        let connections = reg.connections.map { connection -> LinkedComputer in
            var migrated = connection
            migrated.pairing = connection.pairing.migratingRetiredRelay()
            return migrated
        }
        return ConnectionRegistry(connections: connections, preferredId: reg.preferredId)
    }

    static func decodeRegistry(_ data: Data) -> ConnectionRegistry? {
        if let file = try? JSONDecoder().decode(RegistryFile.self, from: data),
           file.v == 1 {
            let connections = file.connections.filter { Pairing.isValidPublic($0.pairing) }
            guard !connections.isEmpty else { return nil }
            let preferred = file.preferredId.flatMap { id in
                connections.contains(where: { $0.id == id }) ? id : nil
            } ?? connections.first?.id
            return ConnectionRegistry(connections: connections, preferredId: preferred)
        }
        // Bare Pairing JSON
        if let pairing = try? JSONDecoder().decode(Pairing.self, from: data),
           Pairing.isValidPublic(pairing) {
            return ConnectionRegistryLogic.upsert(.empty, pairing: pairing)
        }
        return nil
    }
}

private enum KeychainBlob {
    static func load(service: String, account: String) -> Data? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess else {
            return nil
        }
        return item as? Data
    }

    @discardableResult
    static func save(_ data: Data, service: String, account: String) -> Bool {
        let identity: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        let attributes: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
        ]
        let update = SecItemUpdate(identity as CFDictionary, attributes as CFDictionary)
        if update == errSecSuccess { return true }
        guard update == errSecItemNotFound else { return false }
        var item = identity
        attributes.forEach { item[$0.key] = $0.value }
        return SecItemAdd(item as CFDictionary, nil) == errSecSuccess
    }

    static func remove(service: String, account: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        SecItemDelete(query as CFDictionary)
    }
}
