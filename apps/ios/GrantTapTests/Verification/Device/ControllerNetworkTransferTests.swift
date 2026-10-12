import XCTest
@testable import GrantTap

final class ControllerNetworkTransferTests: XCTestCase {
    func testOneTimeControllerBundleRoundTripKeepsComputerKeysSeparate() async throws {
        let mailbox = String(repeating: "a", count: 32)
        let key = Data(repeating: 8, count: 32).base64EncodedString()
            .replacingOccurrences(of: "=", with: "")
        let source = "granttap://pair-v2?v=2&u=https://relay.granttap.com&m=\(mailbox)&k=\(key)"
        var uploaded: Data?
        let uri = try await ControllerNetworkTransfer.publish(
            uris: [source], relay: "wss://relay.granttap.com"
        ) { url, data in
            XCTAssertTrue(url.absoluteString.contains("/pair/"))
            uploaded = data
            return (Data(), HTTPURLResponse(url: url, statusCode: 200,
                                            httpVersion: nil, headerFields: nil)!)
        }
        let link = try XCTUnwrap(ControllerNetworkTransfer.bundleLink(from: uri))
        XCTAssertFalse(uri.contains(source))
        let pairing = validPairing()
        let received = try await ControllerNetworkTransfer.fetch(link, loader: { url in
            (try XCTUnwrap(uploaded), HTTPURLResponse(url: url, statusCode: 200,
                                                        httpVersion: nil, headerFields: nil)!)
        }, pairingFetcher: { request in
            XCTAssertEqual(request.mailboxId, mailbox)
            return .success(pairing)
        })
        XCTAssertEqual(received, [pairing])
    }

    func testInvalidControllerBundleIsRejectedBeforeAnyPairing() async {
        XCTAssertNil(ControllerNetworkTransfer.bundleLink(from: "granttap://controllers?v=1&m=bad&k=bad"))
        do {
            _ = try await ControllerNetworkTransfer.publish(
                uris: ["bad"], relay: "wss://relay.granttap.com"
            ) { url, _ in
                (Data(), HTTPURLResponse(url: url, statusCode: 200,
                                         httpVersion: nil, headerFields: nil)!)
            }
            XCTFail("Invalid component links must not be published")
        } catch { }
    }

    func testControllerBundleSupportsTwentyDistinctComputers() async throws {
        let key = Data(repeating: 8, count: 32).base64EncodedString()
            .replacingOccurrences(of: "=", with: "")
        let links = (0..<20).map { index in
            "granttap://pair-v2?v=2&u=https://relay.granttap.com&m="
                + String(format: "%032x", index + 1) + "&k=\(key)"
        }
        let uri = try await ControllerNetworkTransfer.publish(
            uris: links, relay: "wss://relay.granttap.com"
        ) { url, _ in
            (Data(), HTTPURLResponse(url: url, statusCode: 200,
                                     httpVersion: nil, headerFields: nil)!)
        }
        XCTAssertNotNil(ControllerNetworkTransfer.bundleLink(from: uri))
    }

    @MainActor
    func testComputerInvitationTargetsOnlyChosenComputer() {
        let one = PairingFixture.pairing(room: String(repeating: "a", count: 32))
        let two = PairingFixture.pairing(room: String(repeating: "b", count: 32))
        let model = AppModel()
        model.connectionRegistry = ConnectionRegistryLogic.upsert(
            ConnectionRegistryLogic.upsert(.empty, pairing: one, label: "One"),
            pairing: two, label: "Two")
        ControllerInviteCoordinator.shared.start(using: model, roomId: two.room)
        XCTAssertEqual(ControllerInviteCoordinator.shared.omittedComputerNames, ["Two"])
        XCTAssertTrue(ControllerInviteCoordinator.shared.entries.isEmpty)
    }

    func testAccountDeviceQRIsSeparateFromComputerAndProjectInvites() {
        let code = String(repeating: "A", count: 43)
        let uri = GrantTapAccountAPI.deviceInviteURI(code: code)
        XCTAssertEqual(GrantTapAccountAPI.deviceInviteCode(from: uri), code)
        XCTAssertNil(GrantTapAccountAPI.deviceInviteCode(from: "granttap://pair-v2?code=\(code)"))
        XCTAssertNil(GrantTapAccountAPI.deviceInviteCode(from: "granttap://account?code=bad"))
        XCTAssertNil(ControllerNetworkTransfer.bundleLink(from: uri))
    }

    func testAccountDeviceQRExchangesForIndependentSession() async throws {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [AccountInviteProtocol.self]
        let transport = URLSession(configuration: configuration)
        defer { AccountInviteProtocol.handler = nil; transport.invalidateAndCancel() }
        let owner = GrantTapAccountSession(accountId: UUID().uuidString,
                                           token: String(repeating: "o", count: 43))
        let deviceToken = String(repeating: "n", count: 43)
        let code = String(repeating: "c", count: 43)
        AccountInviteProtocol.handler = { request in
            XCTAssertEqual(request.url?.path, "/api/account/device-invites")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer \(owner.token)")
            return (200, try JSONSerialization.data(withJSONObject: ["code": code,
                "expiresAt": Date().timeIntervalSince1970 * 1_000 + 300_000]))
        }
        let uri = try await GrantTapAccountAPI.issueDeviceInvite(owner, transport: transport)
        XCTAssertEqual(GrantTapAccountAPI.deviceInviteCode(from: uri), code)
        AccountInviteProtocol.handler = { request in
            XCTAssertEqual(request.url?.path, "/api/account/device-invites/redeem")
            XCTAssertNil(request.value(forHTTPHeaderField: "Authorization"))
            let body = try XCTUnwrap(AccountInviteProtocol.body(request))
            XCTAssertEqual((try JSONSerialization.jsonObject(with: body) as? [String: String])?["code"], code)
            return (200, try JSONSerialization.data(withJSONObject: ["accountId": owner.accountId,
                                                                      "token": deviceToken]))
        }
        var stored: GrantTapAccountSession?
        let joined = try await GrantTapAccountAPI.redeemDeviceInvite(code, transport: transport,
            store: { stored = $0; return true })
        XCTAssertEqual(joined.accountId, owner.accountId)
        XCTAssertEqual(stored?.token, deviceToken)
    }

    private func validPairing() -> Pairing {
        let key = Data(repeating: 9, count: 32).base64EncodedString()
        return Pairing(relayUrl: "wss://relay.granttap.com",
                       room: String(repeating: "b", count: 32), role: "phone",
                       deviceName: "Mac", senderId: "controller",
                       myPublicKey: key, mySecretKey: key, peerPublicKey: key,
                       pushAuth: String(repeating: "c", count: 64))
    }
}

private final class AccountInviteProtocol: URLProtocol {
    static var handler: ((URLRequest) throws -> (Int, Data))?
    static func body(_ request: URLRequest) -> Data? {
        if let body = request.httpBody { return body }
        guard let stream = request.httpBodyStream else { return nil }
        stream.open()
        defer { stream.close() }
        var data = Data()
        var bytes = [UInt8](repeating: 0, count: 1_024)
        while stream.hasBytesAvailable {
            let count = stream.read(&bytes, maxLength: bytes.count)
            guard count > 0 else { break }
            data.append(contentsOf: bytes[..<count])
        }
        return data
    }
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
