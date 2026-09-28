import SwiftUI

/// One trusted phone can ask its linked computers for independent, expiring
/// controller credentials. This is a device network, never a Project invite.
@MainActor
final class ControllerInviteCoordinator: ObservableObject {
    static let shared = ControllerInviteCoordinator()

    struct Entry: Identifiable {
        let room: String
        let name: String
        let requestId: String
        let relay: String
        var uri: String? = nil
        var error: String? = nil
        var id: String { room }
    }

    @Published private(set) var entries: [Entry] = []
    @Published private(set) var omittedComputerNames: [String] = []
    @Published private(set) var bundleURI: String?
    @Published private(set) var error: String?
    @Published private(set) var publishing = false

    func start(using model: AppModel) {
        bundleURI = nil
        error = nil
        omittedComputerNames = model.connectionRegistry.connections.filter {
            !$0.pairing.isHub &&
                (model.snapshotForConnection($0).phase != .live
                 || model.relaysByRoom[$0.id] == nil)
        }.map(\.displayName).sorted()
        entries = model.connectionRegistry.connections.compactMap { connection in
            guard !connection.pairing.isHub,
                  model.snapshotForConnection(connection).phase == .live,
                  model.relaysByRoom[connection.id] != nil else { return nil }
            return Entry(room: connection.id, name: connection.displayName,
                         requestId: UUID().uuidString.lowercased(),
                         relay: connection.pairing.relayUrl)
        }
        if entries.isEmpty {
            error = L("Connect at least one computer before inviting another controller.")
        }
        for entry in entries {
            model.relaysByRoom[entry.room]?.send(payload: ControllerPairRequest(
                requestId: entry.requestId, createdAt: Date().timeIntervalSince1970 * 1_000
            ), ttl: 60)
        }
    }

    func receive(_ offer: ControllerPairOffer, fromRoom room: String) {
        guard offer.type == "controller.pair.offer", offer.room == room,
              let index = entries.firstIndex(where: {
                  $0.room == room && $0.requestId == offer.requestId
              }) else { return }
        if offer.status == "ready", let uri = offer.uri,
           Pairing.secureLink(fromURI: uri) != nil,
           let expiresAt = offer.expiresAt,
           expiresAt > Date().timeIntervalSince1970 * 1_000 {
            entries[index].uri = uri
            entries[index].error = nil
        } else {
            entries[index].error = offer.reason ?? L("This computer could not create a code.")
        }
    }

    var readyToPublish: Bool {
        !entries.isEmpty && entries.allSatisfy { $0.uri != nil }
    }

    func publish() async {
        guard readyToPublish, !publishing,
              let relay = entries.first?.relay else { return }
        publishing = true
        error = nil
        defer { publishing = false }
        do {
            bundleURI = try await ControllerNetworkTransfer.publish(
                uris: entries.compactMap(\.uri), relay: relay
            )
        } catch {
            self.error = L("Could not publish the controller code. Try again while computers are Live.")
        }
    }
}
