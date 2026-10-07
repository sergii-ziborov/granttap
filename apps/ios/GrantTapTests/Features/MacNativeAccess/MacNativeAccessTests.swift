#if targetEnvironment(macCatalyst)
import XCTest
@testable import GrantTap

@MainActor
final class MacNativeAccessTests: XCTestCase {
    func testRejectedAccountAuthorizationRecoversThroughLocalConsent() async throws {
        enum Rejected: Error { case account }
        var attempts: [String] = []
        try await MacNativeAccess.authorize(
            accountToken: "saved-account",
            usingAccount: { token in
                attempts.append(token)
                throw Rejected.account
            },
            usingLocalConsent: { attempts.append("local-consent") }
        )
        XCTAssertEqual(attempts, ["saved-account", "local-consent"])
    }

    func testSuccessfulAccountAuthorizationDoesNotOpenLocalConsent() async throws {
        var attempts: [String] = []
        try await MacNativeAccess.authorize(
            accountToken: "saved-account",
            usingAccount: { attempts.append($0) },
            usingLocalConsent: { attempts.append("local-consent") }
        )
        XCTAssertEqual(attempts, ["saved-account"])
    }

    func testCallbackBindsTheCodeToThisNativeAuthorizationAttempt() throws {
        let code = String(repeating: "a", count: 43)
        let valid = try XCTUnwrap(URL(string: "granttap://desktop-auth?code=\(code)&state=expected"))
        XCTAssertEqual(try MacNativeAccess.authorizationCode(valid, expectedState: "expected"), code)
        for value in [
            "https://desktop-auth?code=\(code)&state=expected",
            "granttap://pair?code=\(code)&state=expected",
            "granttap://desktop-auth?code=\(code)&state=other",
            "granttap://desktop-auth?code=\(code)&state=expected&state=expected",
            "granttap://desktop-auth?code=\(code)&code=\(code)&state=expected",
            "granttap://desktop-auth?code=short&state=expected"
        ] {
            XCTAssertThrowsError(try MacNativeAccess.authorizationCode(XCTUnwrap(URL(string: value)),
                expectedState: "expected"))
        }
    }
}
#endif
