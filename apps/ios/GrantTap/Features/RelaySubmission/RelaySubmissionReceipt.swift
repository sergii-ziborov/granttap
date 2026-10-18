import Foundation

struct RelaySubmissionReceipt: Decodable {
    let type: String
    let deliveryId: String
    let reason: String?

    static func isSubmission(_ id: String) -> Bool {
        id.count <= 180 && ["user-message-", "approval-decision-", "attachment-"].contains {
            id.hasPrefix($0) && id.count > $0.count
        }
    }

    static func decode(_ data: Data) -> Self? {
        guard data.count <= 4_096,
              let receipt = try? JSONDecoder().decode(Self.self, from: data),
              ["relay.stored", "relay.dropped"].contains(receipt.type),
              isSubmission(receipt.deliveryId) else { return nil }
        return receipt
    }
}
