import XCTest
@testable import GrantTap

final class AccountComputerChatStatusTests: XCTestCase {
    private func link(relayURL: String = "wss://relay.granttap.com") -> LinkedComputer {
        var pairing = PairingFixture.pairing(room: String(repeating: "a", count: 32))
        pairing.relayUrl = relayURL
        return ConnectionRegistryLogic.upsert(.empty, pairing: pairing).connections[0]
    }

    func testAccountMacShowsTheActualStepBeforeChatsBecomeAvailable() {
        let computer = link()
        let links = [computer]
        func label(_ online: Bool, _ live: Bool, _ routes: [LinkedComputer],
                   _ allowed: Bool, _ active: Set<String>) -> String {
            AccountComputerChatStatus.label(
                online: online, hasChats: live, links: routes,
                allowsManagedTransport: allowed, activeRooms: active)
        }

        XCTAssertEqual(label(false, false, links, true, []), L("Offline"))
        XCTAssertEqual(label(true, false, [], true, []), L("Waiting for encrypted pairing"))
        XCTAssertEqual(label(true, false, links, false, []), L("Relay access unavailable"))
        XCTAssertEqual(label(true, false, links, true, []), L("Waiting for relay connection"))
        XCTAssertEqual(label(true, false, links, true, [computer.id]),
                       L("Online · waiting for secure chat link"))
        XCTAssertEqual(label(true, true, links, false, []), L("Chats available"))
    }

    func testDirectRouteDoesNotRequireManagedRelayEntitlement() {
        let direct = link(relayURL: "wss://example.org")
        XCTAssertEqual(AccountComputerChatStatus.label(
            online: true, hasChats: false, links: [direct],
            allowsManagedTransport: false, activeRooms: [direct.id]),
            L("Online · waiting for secure chat link"))
    }

    func testPresenceAndRetryUseTheSpecificComputer() {
        let computer = AccountComputer(id: "mac", name: "Mac", createdAt: 1,
                                       lastSeenAt: 100_000)
        XCTAssertTrue(AccountComputerChatStatus.isOnline(computer, nowMs: 200_000))
        XCTAssertFalse(AccountComputerChatStatus.isOnline(computer, nowMs: 220_000))
        let unseen = AccountComputer(id: "other", name: "Mac", createdAt: 1, lastSeenAt: nil)
        XCTAssertFalse(AccountComputerChatStatus.isOnline(unseen, nowMs: 200_000))
        XCTAssertTrue(AccountComputerChatStatus.canRetry(online: true, hasChats: false))
        XCTAssertFalse(AccountComputerChatStatus.canRetry(online: true, hasChats: true))
        XCTAssertFalse(AccountComputerChatStatus.canRetry(online: false, hasChats: false))

        let links = [link()]
        XCTAssertFalse(AccountComputerChatStatus.hasChats(links) { _ in false })
        XCTAssertTrue(AccountComputerChatStatus.hasChats(links) { $0.id == links[0].id })
    }
}
