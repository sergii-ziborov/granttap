import Foundation
import XCTest
@testable import GrantTap

@MainActor
final class SubscriptionReceiptSyncTests: XCTestCase {
    private let session = GrantTapAccountSession(
        accountId: "12345678-1234-4123-8123-123456789012", token: String(repeating: "A", count: 43))

    func testPurchaseUsesTheCurrentAccountUUIDAndRequiresSignIn() throws {
        XCTAssertEqual(try ManagedPurchaseIdentity.token(for: session.accountId).uuidString.lowercased(), session.accountId)
        XCTAssertThrowsError(try ManagedPurchaseIdentity.token(for: nil))
        XCTAssertThrowsError(try ManagedPurchaseIdentity.token(for: "invalid"))
        XCTAssertNotNil(ManagedSubscriptionError.signIn.errorDescription)
        XCTAssertNotNil(ManagedSubscriptionError.unboundPurchase.errorDescription)
    }

    func testSignedReceiptUploadPreservesAuthAndNeverSendsAClientSeatCount() async throws {
        let transport = Self.transport()
        defer { transport.invalidateAndCancel() }
        ReceiptURLProtocol.payload = Data("{\"accepted\":true}".utf8)
        try await SubscriptionReceiptSync.upload("signed-fixture", session: session,
            transport: transport, currentSession: { self.session })
        let request = try XCTUnwrap(ReceiptURLProtocol.lastRequest)
        XCTAssertEqual(request.url?.path, "/api/account/subscriptions/receipt")
        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer \(session.token)")
        var bytes = request.httpBody ?? Data()
        if let stream = request.httpBodyStream {
            stream.open(); defer { stream.close() }
            var buffer = [UInt8](repeating: 0, count: 1_024)
            while stream.hasBytesAvailable {
                let count = stream.read(&buffer, maxLength: buffer.count)
                guard count > 0 else { break }
                bytes.append(contentsOf: buffer.prefix(count))
            }
        }
        let body = try XCTUnwrap(JSONSerialization.jsonObject(with: bytes) as? [String: String])
        XCTAssertEqual(body, ["signedTransaction": "signed-fixture"])
        ReceiptURLProtocol.payload = Data("{\"accepted\":false,\"entitlement\":{\"limit\":2}}".utf8)
        try await SubscriptionReceiptSync.upload("signed-fixture", session: session,
            transport: transport, currentSession: { self.session })
    }

    func testAccountSwitchAndUnboundReceiptCannotSharePaidRights() async {
        let transport = Self.transport()
        defer { transport.invalidateAndCancel() }
        do {
            try await SubscriptionReceiptSync.upload("signed-fixture", session: session,
                transport: transport, currentSession: { nil })
            XCTFail("An old account must not upload into a new account")
        } catch { XCTAssertTrue(error is CancellationError) }
        ReceiptURLProtocol.payload = Data("{\"accepted\":false,\"entitlement\":null}".utf8)
        do {
            try await SubscriptionReceiptSync.upload("signed-fixture", session: session,
                transport: transport, currentSession: { self.session })
            XCTFail("An unbound receipt must remain unbound")
        } catch { XCTAssertTrue(error is ManagedSubscriptionError) }
    }

    private static func transport() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [ReceiptURLProtocol.self]
        return URLSession(configuration: configuration)
    }
}

private final class ReceiptURLProtocol: URLProtocol {
    static var payload = Data()
    static var lastRequest: URLRequest?
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        Self.lastRequest = request
        let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Self.payload)
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}
