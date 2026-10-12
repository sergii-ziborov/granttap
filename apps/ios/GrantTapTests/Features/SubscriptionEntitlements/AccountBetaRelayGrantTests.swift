import Foundation
import XCTest
@testable import GrantTap

final class AccountBetaRelayGrantTests: XCTestCase {
    private let session = GrantTapAccountSession(accountId: "owner",
                                                 token: String(repeating: "A", count: 43))

    func testAccountGrantRequiresCurrentSessionAndFutureExpiry() async throws {
        let transport = Self.transport()
        defer { transport.invalidateAndCancel() }
        BetaRelayURLProtocol.payload = Data("{\"expiresAt\":2000000000000}".utf8)
        let grant = try await AccountBetaRelayGrantAPI.load(session: session,
            transport: transport, currentSession: { self.session })
        XCTAssertEqual(grant?.accountID, "owner")
        XCTAssertEqual(grant?.expiresAt.timeIntervalSince1970, 2_000_000_000)
        XCTAssertEqual(BetaRelayURLProtocol.lastPath, "/api/account/beta-relay")
        XCTAssertTrue(BetaRelayURLProtocol.hadAuthorization)

        BetaRelayURLProtocol.payload = Data("{\"expiresAt\":null}".utf8)
        let missingGrant = try await AccountBetaRelayGrantAPI.load(session: session,
            transport: transport, currentSession: { self.session })
        let signedOut = try await AccountBetaRelayGrantAPI.load(session: nil,
            transport: transport, currentSession: { nil })
        XCTAssertNil(missingGrant)
        XCTAssertNil(signedOut)
    }

    func testMalformedGrantAndSessionSwitchCannotAuthorizeRelay() async {
        let transport = Self.transport()
        defer { transport.invalidateAndCancel() }
        BetaRelayURLProtocol.payload = Data("{\"expiresAt\":\"tomorrow\"}".utf8)
        do {
            _ = try await AccountBetaRelayGrantAPI.load(session: session,
                transport: transport, currentSession: { self.session })
            XCTFail("Malformed expiry must be rejected")
        } catch { XCTAssertTrue(error is AccountBridgeError) }

        BetaRelayURLProtocol.payload = Data("{\"expiresAt\":2000000000000}".utf8)
        do {
            _ = try await AccountBetaRelayGrantAPI.load(session: session,
                transport: transport, currentSession: { nil })
            XCTFail("A changed account must not inherit the old grant")
        } catch { XCTAssertTrue(error is CancellationError) }
    }

    private static func transport() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [BetaRelayURLProtocol.self]
        return URLSession(configuration: configuration)
    }
}

private final class BetaRelayURLProtocol: URLProtocol {
    static var payload = Data()
    static var lastPath: String?
    static var hadAuthorization = false

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        Self.lastPath = request.url?.path
        Self.hadAuthorization = request.value(forHTTPHeaderField: "Authorization") != nil
        let response = HTTPURLResponse(url: request.url!, statusCode: 200,
                                       httpVersion: nil, headerFields: nil)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Self.payload)
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}
