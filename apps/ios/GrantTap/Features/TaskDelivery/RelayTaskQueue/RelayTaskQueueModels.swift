import CryptoKit
import Foundation

struct RelayQueuedTask: Codable {
    let type: String
    let jobId: String
    let token: String
    let sessionId: String?
    let notBefore: Double
    let expiresAt: Double
    let createdAt: Double
    let operation: UserMessage
}

enum RelayTaskJobState: String, Codable {
    case queued, accepted, completed, failed, cancelled, expired
}

struct RelayTaskJobReceipt: Decodable {
    let id: String
    let state: RelayTaskJobState
    let notBefore: Double
    let expiresAt: Double
    let resultCode: String?
}

struct RelayTaskQueueReservation: Codable {
    let jobId: String
    let token: String?
    let notBefore: Double
    let expiresAt: Double
    let createdAt: Double
    var envelope: Envelope?
    var cipherDigest: String? = nil
    var uploadAttempted: Bool? = nil
    var serverState: RelayTaskJobState?
    var resultCode: String?

    func uploadBody() throws -> Data {
        struct Upload: Encodable {
            let notBefore: Double
            let expiresAt: Double
            let acceptanceHash: String
            let envelope: Envelope
        }
        guard let envelope, let token else { throw RelayTaskQueueError.invalidMessage }
        let hash = SHA256.hash(data: Data(token.utf8)).map { String(format: "%02x", $0) }.joined()
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(Upload(notBefore: notBefore, expiresAt: expiresAt,
                                             acceptanceHash: hash, envelope: envelope))
        guard data.count <= 22_000_000 else { throw RelayTaskQueueError.tooLarge }
        return data
    }
}

enum RelayTaskQueueError: LocalizedError {
    case invalidMessage, invalidSchedule, tooLarge, unavailable, unsupported, full, conflict, notConfirmed
    var errorDescription: String? {
        switch self {
        case .invalidMessage: return L("This message cannot be saved as a queued task.")
        case .invalidSchedule: return L("Choose a time within the next 29 days.")
        case .tooLarge: return L("Attachments exceed the 11 MB total limit.")
        case .unavailable: return L("Relay is unavailable. This message has not been confirmed as saved.")
        case .unsupported: return L("This relay needs an update before it can store queued tasks.")
        case .full: return L("The relay queue is full. Existing tasks have been kept.")
        case .conflict: return L("This queued task has already changed. Refresh its status before continuing.")
        case .notConfirmed: return L("The relay has not confirmed this change. The task remains in the queue.")
        }
    }
}
