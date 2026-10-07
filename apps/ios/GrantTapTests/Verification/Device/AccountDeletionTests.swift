import Foundation
import TweetNacl
import XCTest
@testable import GrantTap

final class AccountDeletionTests: XCTestCase {
    func testDeletionRequiresServerConfirmationAndSendsOnlySessionToken() async throws {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [AccountDeletionProtocol.self]
        let transport = URLSession(configuration: configuration)
        defer {
            AccountDeletionProtocol.handler = nil
            transport.invalidateAndCancel()
        }
        let session = GrantTapAccountSession(accountId: UUID().uuidString,
                                             token: String(repeating: "t", count: 43))
        let previousSession = GrantTapAccountAPI.session
        defer {
            if let previousSession,
               let data = try? JSONEncoder().encode(previousSession) {
                _ = KeychainPairing.save(data, service: "com.ziborov.granttap.account-session")
            } else { GrantTapAccountAPI.clearSession() }
        }
        XCTAssertTrue(KeychainPairing.save(try JSONEncoder().encode(session),
                                           service: "com.ziborov.granttap.account-session"))
        AccountDeletionProtocol.handler = { request in
            XCTAssertEqual(request.url?.path, "/api/account/me")
            XCTAssertEqual(request.httpMethod, "DELETE")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"),
                           "Bearer \(session.token)")
            XCTAssertNil(request.httpBody)
            return (200, Data("{\"deleted\":false}".utf8))
        }
        do {
            try await GrantTapAccountAPI.deleteAccount(session, transport: transport)
            XCTFail("A successful HTTP status alone must not imply deletion")
        } catch AccountBridgeError.invalidResponse { }
        XCTAssertEqual(GrantTapAccountAPI.session?.accountId, session.accountId)

        AccountDeletionProtocol.handler = { _ in (200, Data("{\"deleted\":true}".utf8)) }
        try await GrantTapAccountAPI.deleteAccount(session, transport: transport)
        XCTAssertNil(GrantTapAccountAPI.session)
    }

    func testDeletionClearsOnlyDeletedAccountLinksAndPreservesQRRouting() {
        let first = PairingFixture.pairing(room: String(repeating: "a", count: 32))
        let second = PairingFixture.pairing(room: String(repeating: "b", count: 32))
        let original = ConnectionRegistryLogic.upsert(
            ConnectionRegistryLogic.upsert(.empty, pairing: first),
            pairing: second, prefer: false)
        let accountA = AccountMachineCredential(accountId: "A", machineId: "1",
                                                machineToken: "first")
        let accountB = AccountMachineCredential(accountId: "B", machineId: "2",
                                                machineToken: "second")
        let linked = ConnectionRegistryLogic.noteAccountLink(
            ConnectionRegistryLogic.noteAccountLink(original, roomId: first.room,
                                                    peerPublicKey: first.peerPublicKey,
                                                    credential: accountA),
            roomId: second.room, peerPublicKey: second.peerPublicKey,
            credential: accountB)
        let result = ConnectionRegistryLogic.clearAccountLinks(linked, accountId: "A")
        XCTAssertEqual(result.preferredId, original.preferredId)
        XCTAssertEqual(result.connections.map(\.pairing), original.connections.map(\.pairing))
        XCTAssertNil(result.connections[0].accountCredential)
        XCTAssertEqual(result.connections[1].accountCredential, accountB)
    }

    @MainActor
    func testDeletedAccountCleanupPersistsAndIsSafeToRepeat() throws {
        let previous = PairedConnectionStore.load()
        defer { _ = PairedConnectionStore.save(previous) }
        let phone = try NaclBox.keyPair()
        let mac = try NaclBox.keyPair()
        let pairing = Pairing(
            relayUrl: "wss://relay.granttap.com", room: String(repeating: "c", count: 32),
            role: "phone", deviceName: "Test Mac", senderId: "test-phone",
            myPublicKey: phone.publicKey.base64EncodedString(),
            mySecretKey: phone.secretKey.base64EncodedString(),
            peerPublicKey: mac.publicKey.base64EncodedString())
        let credential = AccountMachineCredential(accountId: "deleted-account",
                                                  machineId: "old-mac", machineToken: "old-token")
        let linked = ConnectionRegistryLogic.noteAccountLink(
            ConnectionRegistryLogic.upsert(.empty, pairing: pairing),
            roomId: pairing.room, peerPublicKey: pairing.peerPublicKey,
            credential: credential)
        XCTAssertTrue(PairedConnectionStore.save(linked))
        let model = AppModel()
        model.connectionRegistry = linked

        try model.clearDeletedAccountLinks(credential.accountId)
        XCTAssertNil(model.connectionRegistry.connections.first?.accountCredential)
        XCTAssertEqual(model.connectionRegistry.preferredId, linked.preferredId)
        XCTAssertEqual(PairedConnectionStore.load(), model.connectionRegistry)
        try model.clearDeletedAccountLinks(credential.accountId)
        XCTAssertEqual(PairedConnectionStore.load(), model.connectionRegistry)
    }

    @MainActor
    func testControllerQRAddsAnotherComputerWithoutChangingPreferredRoute() throws {
        let previous = PairedConnectionStore.load()
        let phone = try NaclBox.keyPair()
        let mac = try NaclBox.keyPair()
        func pairing(room: String, name: String) -> Pairing {
            Pairing(relayUrl: "wss://127.0.0.1:9", room: room, role: "phone",
                    deviceName: name, senderId: "test-phone",
                    myPublicKey: phone.publicKey.base64EncodedString(),
                    mySecretKey: phone.secretKey.base64EncodedString(),
                    peerPublicKey: mac.publicKey.base64EncodedString())
        }
        let first = pairing(room: String(repeating: "a", count: 32), name: "First Mac")
        let second = pairing(room: String(repeating: "b", count: 32), name: "Second Mac")
        let model = AppModel()
        defer {
            model.relaysByRoom.values.forEach { $0.disconnect() }
            _ = PairedConnectionStore.save(previous)
        }
        model.connectionRegistry = ConnectionRegistryLogic.upsert(.empty, pairing: first)
        XCTAssertFalse(model.addControllerConnections([second, second]))
        XCTAssertEqual(model.connectionRegistry.connections.count, 1)

        XCTAssertTrue(model.addControllerConnections([second]))
        XCTAssertEqual(Set(model.connectionRegistry.connections.map(\.id)),
                       Set([first.room, second.room]))
        XCTAssertEqual(model.connectionRegistry.preferredId, first.room)
        XCTAssertEqual(PairedConnectionStore.load(), model.connectionRegistry)
    }
}

private final class AccountDeletionProtocol: URLProtocol {
    static var handler: ((URLRequest) throws -> (Int, Data))?

    override class func canInit(with request: URLRequest) -> Bool {
        request.url?.host == "granttap.com"
    }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        do {
            let (status, data) = try Self.handler!(request)
            let response = HTTPURLResponse(url: request.url!, statusCode: status,
                                           httpVersion: "HTTP/1.1", headerFields: nil)!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch { client?.urlProtocol(self, didFailWithError: error) }
    }
    override func stopLoading() { }
}
