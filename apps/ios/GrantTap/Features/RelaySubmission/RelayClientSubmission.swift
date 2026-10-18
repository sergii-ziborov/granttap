import Foundation

extension RelayClient {
    func transmitEnvelope(_ text: String, deliveryId: String?, to: String,
                          completion: ((Error?) -> Void)?) {
        guard let socket = task else { completion?(RelaySendError.disconnected); return }
        guard role == .phone, to == "machine", let deliveryId, let completion,
              RelaySubmissionReceipt.isSubmission(deliveryId) else {
            socket.send(.string(text)) { completion?($0) }
            return
        }
        guard let token = relaySubmissions.register(deliveryId, completion: completion) else { return }
        socket.send(.string(text)) { [weak self] error in
            if let error { self?.relaySubmissions.complete(deliveryId, error: error) }
        }
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 5) { [weak self] in
            self?.relaySubmissions.expire(deliveryId, token: token)
        }
    }

    func handleSubmissionControl(_ data: Data) -> Bool {
        guard let receipt = RelaySubmissionReceipt.decode(data) else { return false }
        let error: Error? = receipt.type == "relay.stored" ? nil
            : receipt.reason == "full" ? RelaySubmissionFailure.capacity : RelaySubmissionFailure.rejected
        relaySubmissions.complete(receipt.deliveryId, error: error)
        return true
    }
}

extension RelaySubmissionFailure: LocalizedError {
    var errorDescription: String? {
        switch self {
        case .notConfirmed: return L("Relay has not confirmed saving this submission. Retrying…")
        case .disconnected: return L("Relay is offline. Your submission remains saved on this device.")
        case .rejected: return L("Relay could not save this submission. It remains on this device.")
        case .capacity: return L("The relay queue is full. Your submission remains on this device.")
        }
    }
}
