import Foundation
import XCTest
@testable import GrantTap

final class AccountRecoveryFailureTests: XCTestCase {
    @MainActor
    func testLegacyQRGrantStaysWithItsOriginalAccount() async throws {
        let credential = AccountMachineCredential(
            accountId: "original", machineId: "original-mac",
            machineToken: String(repeating: "t", count: 43))
        let pairing = PairingFixture.pairing(room: String(repeating: "a", count: 32))
        var legacy = ConnectionRegistryLogic.upsert(.empty, pairing: pairing)
        legacy.connections[0].accountCredential = credential
        legacy.connections[0].accountReference = nil
        let model = AppModel()
        model.connectionRegistry = legacy

        try await model.linkLocalComputersToAccount(
            GrantTapAccountSession(accountId: "other", token: "unused"))
        XCTAssertEqual(model.connectionRegistry.connections[0].accountCredential?.accountId,
                       "original")
        try await model.linkLocalComputersToAccount(
            GrantTapAccountSession(accountId: "original", token: "unused"))
        XCTAssertEqual(model.connectionRegistry.connections[0].accountCredential, credential)
        XCTAssertNil(model.connectionRegistry.connections[0].accountReference)
    }

    func testInvalidRecoveryRequestIdCannotCreateAPairing() async throws {
        let transport = stubTransport()
        defer { RecoveryURLProtocol.handler = nil; transport.invalidateAndCancel() }
        RecoveryURLProtocol.handler = { _ in (200, Data("{\"id\":\"bad\"}".utf8)) }
        do {
            _ = try await AccountRecovery.connect(machine, session: session,
                                                  transport: transport, pollDelayNanoseconds: 0)
            XCTFail("The account service must return a valid request ID")
        } catch AccountBridgeError.invalidResponse { }
    }

    func testPendingRecoveryEventuallyExpires() async throws {
        let transport = stubTransport()
        defer { RecoveryURLProtocol.handler = nil; transport.invalidateAndCancel() }
        let requestId = UUID().uuidString.lowercased()
        var polls = 0
        RecoveryURLProtocol.handler = { request in
            if request.httpMethod == "POST" {
                return (200, Data("{\"id\":\"\(requestId)\"}".utf8))
            }
            polls += 1
            return (200, Data("{\"status\":\"pending\"}".utf8))
        }
        do {
            _ = try await AccountRecovery.connect(machine, session: session,
                                                  transport: transport, pollDelayNanoseconds: 0)
            XCTFail("A Mac that never offers a route must not be treated as linked")
        } catch AccountBridgeError.expired { }
        XCTAssertEqual(polls, 75)
    }

    func testReadyRequestWithoutSealedOfferIsRejected() async throws {
        let transport = stubTransport()
        defer { RecoveryURLProtocol.handler = nil; transport.invalidateAndCancel() }
        let requestId = UUID().uuidString.lowercased()
        RecoveryURLProtocol.handler = { request in
            if request.httpMethod == "POST" {
                return (200, Data("{\"id\":\"\(requestId)\"}".utf8))
            }
            return (200, Data("{\"status\":\"ready\"}".utf8))
        }
        do {
            _ = try await AccountRecovery.connect(machine, session: session,
                                                  transport: transport, pollDelayNanoseconds: 0)
            XCTFail("Account identity alone must not create a chat route")
        } catch AccountBridgeError.invalidResponse { }
    }

    func testComputerListRejectsRepeatedCursorAndUnboundedPages() async throws {
        let transport = stubTransport()
        defer { RecoveryURLProtocol.handler = nil; transport.invalidateAndCancel() }
        RecoveryURLProtocol.handler = { _ in
            (200, Data("{\"machines\":[],\"nextCursor\":\"repeat\"}".utf8))
        }
        do {
            _ = try await AccountRecovery.computers(session: session, transport: transport)
            XCTFail("Repeated pages must not loop forever")
        } catch AccountBridgeError.invalidResponse { }

        var pages = 0
        RecoveryURLProtocol.handler = { _ in
            pages += 1
            return (200, Data("{\"machines\":[],\"nextCursor\":\"page-\(pages)\"}".utf8))
        }
        do {
            _ = try await AccountRecovery.computers(session: session, transport: transport)
            XCTFail("A server must not make the phone scan unlimited pages")
        } catch AccountBridgeError.invalidResponse { }
        XCTAssertEqual(pages, 100)
    }

    private var session: GrantTapAccountSession {
        GrantTapAccountSession(accountId: UUID().uuidString, token: String(repeating: "t", count: 43))
    }

    private var machine: AccountComputer {
        AccountComputer(id: UUID().uuidString.lowercased(), name: "Test Mac",
                        createdAt: 1, lastSeenAt: nil)
    }

    private func stubTransport() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [RecoveryURLProtocol.self]
        return URLSession(configuration: configuration)
    }
}

private final class RecoveryURLProtocol: URLProtocol {
    static var handler: ((URLRequest) -> (Int, Data))?

    override class func canInit(with request: URLRequest) -> Bool {
        request.url?.host == "granttap.com"
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let (status, body) = Self.handler!(request)
        let response = HTTPURLResponse(url: request.url!, statusCode: status,
                                       httpVersion: "HTTP/1.1", headerFields: nil)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: body)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() { }
}
