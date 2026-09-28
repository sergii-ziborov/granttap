import XCTest
@testable import GrantTap

@MainActor
final class ProviderHookReviewTests: XCTestCase {
    private func hook(_ status: String = "modified", enabled: Bool = true) -> ProviderHookInfo {
        ProviderHookInfo(event: "PreToolUse", trustStatus: status, enabled: enabled,
            key: "policy", currentHash: "hash", command: "node granttap internal hook codex-policy")
    }

    func testHookReadinessKeepsConfigurationTrustAndEnablingSeparate() throws {
        XCTAssertFalse(hook().isActive)
        XCTAssertTrue(hook().canReview)
        XCTAssertTrue(hook("trusted").isActive)
        XCTAssertFalse(hook("trusted", enabled: false).isActive)
        for state in ["unknown", "missing", "future"] {
            XCTAssertFalse(hook(state).canReview)
            XCTAssertFalse(hook(state).isActive)
            XCTAssertFalse(hook(state).title.isEmpty)
        }
        XCTAssertFalse(hook().purpose.isEmpty)
        XCTAssertFalse(ProviderHookInfo(event: "PermissionRequest", trustStatus: "untrusted", enabled: true).purpose.isEmpty)
        let legacy = try JSONDecoder().decode(AgentIntegrationInfo.self,
            from: Data(#"{"agent":"codex","installed":true,"hookConfigured":true}"#.utf8))
        XCTAssertNil(legacy.hooks)
        XCTAssertNil(legacy.endpointId)
        XCTAssertEqual(ProviderHookInfo.summary(nil), L("Unknown"))
        let permission = ProviderHookInfo(event: "PermissionRequest", trustStatus: "trusted", enabled: true)
        XCTAssertEqual(ProviderHookInfo.summary([hook("trusted"), permission]), L("Ready"))
        XCTAssertEqual(ProviderHookInfo.summary([hook(), permission]), L("Needs review"))
        XCTAssertEqual(ProviderHookInfo.summary([hook("trusted", enabled: false), permission]), L("Disabled in Codex"))
        XCTAssertEqual(ProviderHookInfo.summary([hook("unknown"), permission]), L("Unknown"))
        XCTAssertEqual(ProviderHookInfo.summary([hook("missing"), permission]), L("Not configured"))
        XCTAssertEqual(ProviderHookInfo.summary([hook("trusted"), hook("trusted")]), L("Unknown"))
    }

    func testOnlyTheReviewedComputerAndHashCanConfirmTheRequest() throws {
        let model = AppModel()
        var sent: ProviderHookTrust?
        XCTAssertTrue(model.reviewProviderHook(hook(), room: "room-a", endpointId: "mac-a") { sent = $0 })
        let request = try XCTUnwrap(sent)
        XCTAssertEqual(request.currentHash, "hash")
        XCTAssertFalse(model.reviewProviderHook(hook(), room: "room-a", endpointId: "mac-a") { _ in })
        let key = AppModel.hookReviewKey(room: "room-a", event: "PreToolUse")
        func result(endpoint: String = "mac-a", hash: String = "hash") -> ProviderHookTrustResult {
            var applied = hook("trusted")
            applied.currentHash = hash
            return ProviderHookTrustResult(type: "provider.hook.trust.result", agent: "codex",
                endpointId: endpoint, requestId: request.requestId, ok: true, message: "Confirmed",
                hooks: [applied], checkedAt: 1)
        }
        model.receive(result(endpoint: "mac-b"), fromRoom: "room-a")
        model.receive(result(), fromRoom: "room-b")
        model.receive(result(hash: "different"), fromRoom: "room-a")
        guard case .pending = model.providerHookReviews[key] else {
            return XCTFail("a different scope or definition cannot confirm trust")
        }
        model.receive(result(), fromRoom: "room-a")
        guard case .finished(let applied) = model.providerHookReviews[key] else {
            return XCTFail("native confirmation should complete the review")
        }
        XCTAssertTrue(applied.ok)
        XCTAssertFalse(model.reviewProviderHook(hook("unknown"), room: "room-a", endpointId: "mac-a") { _ in })
    }

    func testMissingTransportAndUnconfirmedNativeStateCannotCompleteAReview() throws {
        let model = AppModel()
        XCTAssertFalse(model.reviewProviderHook(hook(), room: "missing", endpointId: "mac"))
        XCTAssertTrue(model.providerHookReviews.isEmpty)
        var request: ProviderHookTrust?
        XCTAssertTrue(model.reviewProviderHook(hook(), room: "room", endpointId: "mac") { request = $0 })
        let sent = try XCTUnwrap(request)
        let key = AppModel.hookReviewKey(room: "room", event: "PreToolUse")
        for applied in [hook("untrusted"), hook("trusted", enabled: false)] {
            model.receive(ProviderHookTrustResult(type: "provider.hook.trust.result", agent: "codex",
                endpointId: "mac", requestId: sent.requestId, ok: true, message: "incorrect",
                hooks: [applied], checkedAt: 1), fromRoom: "room")
            guard case .pending = model.providerHookReviews[key] else { return XCTFail("not confirmed") }
        }
        model.receive(ProviderHookTrustResult(type: "provider.hook.trust.result", agent: "codex",
            endpointId: "mac", requestId: sent.requestId, ok: false, message: "changed",
            hooks: [hook("modified")], checkedAt: 1), fromRoom: "room")
        guard case .finished(let result) = model.providerHookReviews[key] else { return XCTFail("failed receipt missing") }
        XCTAssertFalse(result.ok)
    }
}
