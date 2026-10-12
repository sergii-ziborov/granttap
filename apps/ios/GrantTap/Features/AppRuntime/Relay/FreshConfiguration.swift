import Foundation

extension RelayClient {
    @discardableResult
    func sendFreshConfiguration(_ value: ConfigSet) -> String {
        let id = UUID().uuidString.lowercased()
        if let body = Self.freshConfigurationPayload(value, instanceEpoch: latestConfigEpoch, operationId: id) {
            sendRaw(body, ttl: 60, deliveryId: id)
        }
        return id
    }

    static func freshConfigurationPayload(_ value: ConfigSet, instanceEpoch: String?,
                                          operationId: String) -> Data? {
        guard let encoded = try? encodeOmittingNulls(value),
              var body = try? JSONSerialization.jsonObject(with: encoded) as? [String: Any] else { return nil }
        body["operationId"] = operationId
        body["expiresAt"] = value.createdAt + 60_000
        if let instanceEpoch { body["instanceEpoch"] = instanceEpoch }
        if let session = value.autoAcceptSession, session.level == nil,
           var action = body["autoAcceptSession"] as? [String: Any] {
            action["level"] = NSNull()
            body["autoAcceptSession"] = action
        }
        return try? JSONSerialization.data(withJSONObject: body)
    }
}
