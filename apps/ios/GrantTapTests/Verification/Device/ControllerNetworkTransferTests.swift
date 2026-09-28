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

    private func validPairing() -> Pairing {
        let key = Data(repeating: 9, count: 32).base64EncodedString()
        return Pairing(relayUrl: "wss://relay.granttap.com",
                       room: String(repeating: "b", count: 32), role: "phone",
                       deviceName: "Mac", senderId: "controller",
                       myPublicKey: key, mySecretKey: key, peerPublicKey: key,
                       pushAuth: String(repeating: "c", count: 64))
    }
}
