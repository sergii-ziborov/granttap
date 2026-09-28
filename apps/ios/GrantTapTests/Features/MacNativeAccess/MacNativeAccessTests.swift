#if targetEnvironment(macCatalyst)
import XCTest
@testable import GrantTap

@MainActor
final class MacNativeAccessTests: XCTestCase {
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
