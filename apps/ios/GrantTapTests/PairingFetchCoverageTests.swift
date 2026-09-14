import XCTest
@testable import GrantTap

final class PairingFetchCoverageTests: XCTestCase {
    func testSecurePairingRejectsInvalidRouteMailboxAndTransferKey() async {
        let key = transferKey()
        assertPairingError(.badCode, result: await Pairing.fetchSecurePairing(
            relayBase: "http://example.com", mailboxId: mailbox(), transferKey: key
        ))
        assertPairingError(.badCode, result: await Pairing.fetchSecurePairing(
            relayBase: "relay.granttap.app", mailboxId: "short", transferKey: key
        ))
        assertPairingError(.badCode, result: await Pairing.fetchSecurePairing(
            relayBase: "relay.granttap.app", mailboxId: mailbox(), transferKey: "bad"
        ))
    }

    func testSecurePairingMapsHTTPMalformedAndTransportFailures() async {
        let url = URL(string: "https://relay.granttap.app/pair/\(mailbox())")!
        let expired = await Pairing.fetchSecurePairing(
            relayBase: "relay.granttap.app", mailboxId: mailbox(), transferKey: transferKey()
        ) { _ in
            (Data(), HTTPURLResponse(
                url: url, statusCode: 410, httpVersion: nil, headerFields: nil
            )!)
        }
        assertPairingError(.codeExpiredOrUsed, result: expired)

        let malformed = await Pairing.fetchSecurePairing(
            relayBase: "relay.granttap.app", mailboxId: mailbox(), transferKey: transferKey()
        ) { _ in
            (Data("{}".utf8), HTTPURLResponse(
                url: url, statusCode: 200, httpVersion: nil, headerFields: nil
            )!)
        }
        assertPairingError(.badCode, result: malformed)

        let unreachable = await Pairing.fetchSecurePairing(
            relayBase: "relay.granttap.app", mailboxId: mailbox(), transferKey: transferKey()
        ) { _ in throw PairingFetchFixtureError.offline }
        assertPairingError(.unreachable, result: unreachable)
    }

    func testSecurePairingOpensAndValidatesEncryptedMailboxPayload() async throws {
        let key = transferKey()
        let pairing = validPairing()
        let plain = try JSONEncoder().encode(pairing)
        let sealed = try XCTUnwrap(Crypto.openableSeal(plain, key: key))
        let blob = try JSONSerialization.data(withJSONObject: [
            "nonce": sealed.nonce, "box": sealed.box,
        ])
        let result = await Pairing.fetchSecurePairing(
            relayBase: "relay.granttap.app", mailboxId: mailbox(), transferKey: key
        ) { url in
            XCTAssertTrue(url.absoluteString.hasSuffix("/pair/\(self.mailbox())"))
            return (blob, HTTPURLResponse(
                url: url, statusCode: 200, httpVersion: nil, headerFields: nil
            )!)
        }
        guard case .success(let decoded) = result else {
            return XCTFail("Expected valid encrypted pairing")
        }
        XCTAssertEqual(decoded, pairing)
    }

    private func assertPairingError(
        _ expected: PairingError, result: Result<Pairing, PairingError>
    ) {
        guard case .failure(let actual) = result else {
            return XCTFail("Expected pairing failure")
        }
        XCTAssertEqual(String(describing: actual), String(describing: expected))
    }

    private func mailbox() -> String { String(repeating: "a", count: Pairing.mailboxLength) }

    private func transferKey() -> String {
        Data(repeating: 7, count: 32).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    private func validPairing() -> Pairing {
        let key = Data(repeating: 9, count: 32).base64EncodedString()
        return Pairing(
            relayUrl: "wss://relay.granttap.app", room: String(repeating: "b", count: 32),
            role: "phone", deviceName: "Test Mac", senderId: "sender",
            myPublicKey: key, mySecretKey: key, peerPublicKey: key,
            pushAuth: String(repeating: "c", count: 64)
        )
    }
}

private enum PairingFetchFixtureError: Error { case offline }
