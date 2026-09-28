import XCTest
@testable import GrantTap

@MainActor
final class CapabilityCatalogTests: XCTestCase {
    func testCatalogUsesAuthenticatedRoomAndPreservesProviderWorkspaceIdentity() throws {
        let status = CapabilityCatalogStatus(
            type: "capability.catalog.status",
            computerId: "claimed-other-room",
            machine: "Sergii MacBook",
            entries: [
                CapabilityCatalogEntry(provider: "codex", workspace: "/work/a", kind: .mcp,
                                       name: "granttap", available: true, allowed: true),
                CapabilityCatalogEntry(provider: "grok", workspace: "/work/b", kind: .mcp,
                                       name: "granttap", available: true, allowed: false),
            ],
            generatedAt: 123
        )
        let decoded = try JSONDecoder().decode(
            CapabilityCatalogStatus.self,
            from: JSONEncoder().encode(status)
        )
        let store = CapabilityCatalogStore()

        store.apply(decoded, fromRoom: "authenticated-room")

        XCTAssertEqual(store.rows.map(\.roomId), ["authenticated-room", "authenticated-room"])
        XCTAssertEqual(store.rows.map(\.provider), ["codex", "grok"])
        XCTAssertEqual(store.rows.map(\.workspace), ["/work/a", "/work/b"])
        XCTAssertEqual(Set(store.rows.map(\.machine)), ["Sergii MacBook"])
    }

    func testCatalogToggleUpdatesOnlyExactComputerAndCapability() {
        let store = CapabilityCatalogStore()
        let entry = CapabilityCatalogEntry(provider: "codex", workspace: nil, kind: .mcp,
                                           name: "granttap", available: true, allowed: true)
        store.apply(CapabilityCatalogStatus(type: "capability.catalog.status", computerId: "a",
                                            machine: "Mac A", entries: [entry], generatedAt: 1),
                    fromRoom: "room-a")
        store.apply(CapabilityCatalogStatus(type: "capability.catalog.status", computerId: "b",
                                            machine: "Mac B", entries: [entry], generatedAt: 1),
                    fromRoom: "room-b")

        store.setAllowed(false, kind: .mcp, name: "granttap", roomId: "room-b")

        XCTAssertEqual(store.rows.first(where: { $0.roomId == "room-a" })?.allowed, true)
        XCTAssertEqual(store.rows.first(where: { $0.roomId == "room-b" })?.allowed, false)
    }
}
