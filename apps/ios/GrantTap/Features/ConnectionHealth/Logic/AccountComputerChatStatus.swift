import Foundation

/// A Mac appearing in the account roster proves identity, not an open chat route.
enum AccountComputerChatStatus {
    static func isOnline(_ computer: AccountComputer, nowMs: Double) -> Bool {
        guard let seen = computer.lastSeenAt else { return false }
        return nowMs - seen < 120_000
    }

    static func hasChats(_ links: [LinkedComputer],
                         isLive: (LinkedComputer) -> Bool) -> Bool {
        links.contains(where: isLive)
    }

    static func canRetry(online: Bool, hasChats: Bool) -> Bool {
        online && !hasChats
    }

    static func label(
        online: Bool, hasChats: Bool, links: [LinkedComputer],
        allowsManagedTransport: Bool, activeRooms: Set<String>
    ) -> String {
        if hasChats { return L("Chats available") }
        guard online else { return L("Offline") }
        guard !links.isEmpty else { return L("Waiting for encrypted pairing") }
        if links.contains(where: {
            DeviceEndpointDirectory.isManaged($0.pairing.relayUrl)
                && $0.pairing.directoryUrl == nil
        }) && !allowsManagedTransport {
            return L("Relay access unavailable")
        }
        if links.allSatisfy({ !activeRooms.contains($0.id) }) {
            return L("Waiting for relay connection")
        }
        return L("Online · waiting for secure chat link")
    }
}
