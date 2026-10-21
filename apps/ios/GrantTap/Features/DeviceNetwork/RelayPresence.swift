import Foundation

struct RelayPresence: Decodable, Equatable {
    struct Device: Decodable, Equatable {
        let id: String
        let role: String
        let online: Bool
        let lastSeenAt: Double
    }
    let type: String
    let room: String
    let generatedAt: Double
    let devices: [Device]

    static func decode(_ data: Data, room: String, now: Double) -> RelayPresence? {
        guard data.count <= 12_000, let value = try? JSONDecoder().decode(Self.self, from: data),
              value.type == "relay.presence", value.room == room, value.devices.count <= 32,
              value.generatedAt.isFinite, value.generatedAt > 0, value.generatedAt <= now + 30_000,
              value.devices.allSatisfy({ device in
                  device.id.range(of: "^[a-f0-9]{64}$", options: .regularExpression) != nil
                      && ["machine", "phone"].contains(device.role)
                      && device.lastSeenAt.isFinite && device.lastSeenAt > 0
                      && device.lastSeenAt <= value.generatedAt + 30_000
              }) else { return nil }
        return value
    }
}

extension RelayClient {
    func handleRelayPresence(_ data: Data) -> Bool {
        guard let value = RelayPresence.decode(data, room: pairing.room,
            now: Date().timeIntervalSince1970 * 1_000) else { return false }
        DispatchQueue.main.async { self.onRelayPresence?(value) }
        return true
    }
}
