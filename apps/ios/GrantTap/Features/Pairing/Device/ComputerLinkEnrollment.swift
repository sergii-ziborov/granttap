import Foundation
import SwiftUI

/// Adds a computer through its one-use mailbox, without replacing other links.
@MainActor
final class ComputerLinkEnrollment: ObservableObject {
    enum Phase: Equatable {
        case idle, invalidLink, wrongPurpose, expired, unavailable, storageFailed, saved
    }
    typealias Fetch = (Pairing.SecureLink) async -> Result<Pairing, PairingError>
    typealias NetworkFetch = (Pairing.SecureLink) async throws -> [Pairing]
    @Published private(set) var phase: Phase = .idle
    @Published private(set) var busy = false
    @Published private(set) var addedComputers = 0
    private let fetch: Fetch
    private let networkFetch: NetworkFetch
    private let store: (Pairing) -> Bool
    private let storeNetwork: (([Pairing]) -> Bool)?

    init(fetch: @escaping Fetch = { link in
        await Pairing.fetchSecurePairing(relayBase: link.relayBase,
                                        mailboxId: link.mailboxId, transferKey: link.transferKey)
    }, networkFetch: @escaping NetworkFetch = { try await ControllerNetworkTransfer.fetch($0) },
         store: @escaping (Pairing) -> Bool, storeNetwork: (([Pairing]) -> Bool)? = nil) {
        self.fetch = fetch
        self.networkFetch = networkFetch
        self.store = store
        self.storeNetwork = storeNetwork
    }

    func connect(_ text: String) async {
        guard !busy else { return }
        phase = .idle
        addedComputers = 0
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.utf8.count <= 4_096, let link = ControllerNetworkTransfer.bundleLink(from: trimmed) {
            await connectNetwork(link)
            return
        }
        guard trimmed.utf8.count <= 4_096, let link = Pairing.secureLink(fromURI: trimmed),
              Pairing.normalizedPairingHTTPBase(link.relayBase) != nil else {
            phase = .invalidLink
            return
        }
        busy = true
        defer { busy = false }
        switch await fetch(link) {
        case .success(let pairing):
            guard Pairing.isValid(pairing), !pairing.isHub, pairing.inviteKind == nil else {
                phase = .wrongPurpose
                return
            }
            phase = store(pairing) ? .saved : .storageFailed
            addedComputers = phase == .saved ? 1 : 0
        case .failure(.codeExpiredOrUsed): phase = .expired
        case .failure(.badCode): phase = .invalidLink
        case .failure: phase = .unavailable
        }
    }

    private func connectNetwork(_ link: Pairing.SecureLink) async {
        busy = true
        addedComputers = 0
        defer { busy = false }
        do {
            let pairings = try await networkFetch(link)
            guard (1...16).contains(pairings.count), Set(pairings.map(\.room)).count == pairings.count,
                  pairings.allSatisfy({ Pairing.isValid($0) && !$0.isHub && $0.inviteKind == nil }) else {
                phase = .wrongPurpose
                return
            }
            phase = storeNetwork?(pairings) == true ? .saved : .storageFailed
            if phase == .saved { addedComputers = pairings.count }
        } catch ControllerNetworkTransfer.TransferError.expired {
            phase = .expired
        } catch ControllerNetworkTransfer.TransferError.incomplete {
            phase = .expired
        } catch { phase = .unavailable }
    }

    var message: String? {
        switch phase {
        case .idle: return nil
        case .invalidLink: return L("Paste a valid computer or device network connection link.")
        case .wrongPurpose: return L("This invite is not a computer connection link.")
        case .expired: return L("This connection link expired or was already used. Generate a new one on the computer or in your iPhone's device network settings.")
        case .unavailable: return L("Could not retrieve the computer connection. Check the network and retry.")
        case .storageFailed: return L("Could not save this connection. Your existing connections are unchanged.")
        case .saved:
            return addedComputers > 1
                ? String(format: L("%d computers added. Waiting for them to come online."), addedComputers)
                : L("Computer added. Waiting for it to come online.")
        }
    }
}
