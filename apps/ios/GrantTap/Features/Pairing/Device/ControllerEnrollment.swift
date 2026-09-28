import Foundation
import SwiftUI

struct ControllerEnrollmentCode: Decodable {
    enum Status: String, Decodable { case idle, pending, connected, expired, unavailable }
    let operation: String
    let status: Status
    let computer: String
    let expires_at: Double?
    let uri: String?

    func isValid(now: Double) -> Bool {
        guard operation == "desktop.controller_enrollment", !computer.isEmpty,
              computer.utf8.count <= 160 else { return false }
        if status == .pending {
            guard let uri, uri.utf8.count <= 4_096,
                  let link = Pairing.secureLink(fromURI: uri),
                  Pairing.normalizedPairingHTTPBase(link.relayBase) != nil,
                  let expires_at, expires_at.isFinite, expires_at > now,
                  expires_at <= now + 16 * 60_000 else { return false }
        } else if uri != nil { return false }
        return true
    }
}

/// The private local MCP issues and confirms this specific controller enrollment.
@MainActor
final class ControllerEnrollment: ObservableObject {
    typealias Read = (String) async throws -> Data
    @Published private(set) var code: ControllerEnrollmentCode?
    @Published private(set) var busy = false
    @Published private(set) var failed = false
    private var generation = 0

    func create(read: Read) async { await perform("create", read: read) }
    func refresh(read: Read) async { await perform("status", read: read) }

    func clear() {
        generation += 1
        code = nil
        busy = false
        failed = false
    }

    private func perform(_ action: String, read: Read) async {
        guard !busy else { return }
        busy = true
        failed = false
        let revision = generation
        defer { if generation == revision { busy = false } }
        do {
            let data = try await read(action)
            guard generation == revision, !Task.isCancelled else { return }
            let decoded = try JSONDecoder().decode(ControllerEnrollmentCode.self, from: data)
            guard decoded.isValid(now: Date().timeIntervalSince1970 * 1_000) else {
                throw PairingError.badCode
            }
            code = decoded
            failed = decoded.status == .unavailable
        } catch {
            guard generation == revision, !Task.isCancelled else { return }
            code = nil
            failed = true
        }
    }
}
