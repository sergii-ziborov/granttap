import XCTest
@testable import GrantTap

final class ConfigCommandContextTests: XCTestCase {
    func testDigestMatchesTheMacCanonicalBody() {
        let payload = ConfigSet(
            type: "config.set",
            meshEnabled: false,
            createdAt: 1
        )
        XCTAssertEqual(ConfigCommandContext.digest(payload).count, 64)
        XCTAssertNotEqual(
            ConfigCommandContext.digest(payload),
            ConfigCommandContext.digest(ConfigSet(
                type: "config.set", meshEnabled: true, createdAt: 1
            ))
        )
        let signed = ConfigCommandContext.signed(meshEnabled: false, baseRevision: 0, instanceEpoch: "epoch-1")
        XCTAssertEqual(signed.operationId?.count ?? 0, 36)
        XCTAssertEqual(signed.baseRevision, 0)
        XCTAssertEqual(signed.instanceEpoch, "epoch-1")
        XCTAssertEqual(signed.payloadDigest?.count, 64)
    }
}
