import Foundation
import Testing
@testable import DesktopInspectorCore

@Test func desktopMCPStatusShowsRelayAndProviderReadiness() throws {
    let body = Data(#"{"schema":"granttap.desktop-status.v1","ok":true,"service":"granttap-mcp","computer":"Mac","version":"0.8.24","paired":true,"phoneReachability":"offline","phones":[],"relayHost":"relay.granttap.com","relayStatus":"online","providers":[{"id":"codex","status":"connected","detail":"Ready"}],"desktopEngineSocket":"/tmp/granttap-desktop-test/engine.sock"}"#.utf8)
    let status = try LocalMCPStatus.decode(body)
    #expect(status.relayHost == "relay.granttap.com")
    #expect(status.relayStatus == .online)
    #expect(status.providers.map(\.id) == ["codex"])
    #expect(status.providers[0].detail == "Ready")
    #expect(status.desktopEngineSocket == "/tmp/granttap-desktop-test/engine.sock")

    let unrelated = Data(#"{"schema":"other","ok":true,"service":"granttap-mcp"}"#.utf8)
    #expect(throws: LocalMCPStatus.Error.unrecognizedService) {
        _ = try LocalMCPStatus.decode(unrelated)
    }
}
