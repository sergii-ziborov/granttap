import XCTest
@testable import GrantTap

@MainActor
final class ComputerLinkEnrollmentTests: XCTestCase {
    func testInvalidLinkNeverFetchesOrStores() async {
        var fetched = false
        var stored = false
        let enrollment = ComputerLinkEnrollment(fetch: { _ in
            fetched = true
            return .failure(.unreachable)
        }, store: { _ in stored = true; return true })
        XCTAssertNil(enrollment.message)
        await enrollment.connect("not a computer link")
        XCTAssertFalse(fetched)
        XCTAssertFalse(stored)
        XCTAssertEqual(enrollment.phase, .invalidLink)
        XCTAssertNotNil(enrollment.message)
    }

    func testConnectStoresComputerOnlyAndWaitsForLiveConnection() async {
        let pairing = computer()
        var saved: Pairing?
        let enrollment = ComputerLinkEnrollment(fetch: { _ in .success(pairing) },
                                                store: { saved = $0; return true })
        await enrollment.connect(link())
        XCTAssertEqual(saved, pairing)
        XCTAssertEqual(enrollment.phase, .saved)
        XCTAssertNotNil(enrollment.message)
        XCTAssertFalse(enrollment.busy)
    }

    func testMeshInviteAndKeychainFailureNeverClaimConnected() async {
        var invite = computer()
        invite.hub = true
        var stored = false
        let rejected = ComputerLinkEnrollment(fetch: { _ in .success(invite) },
                                              store: { _ in stored = true; return true })
        await rejected.connect(link())
        XCTAssertFalse(stored)
        XCTAssertEqual(rejected.phase, .wrongPurpose)
        XCTAssertNotNil(rejected.message)
        let failed = ComputerLinkEnrollment(fetch: { _ in .success(self.computer()) },
                                            store: { _ in false })
        await failed.connect(link())
        XCTAssertEqual(failed.phase, .storageFailed)
        XCTAssertNotNil(failed.message)
    }

    func testExpiredAndUnreachableLinkCanRetry() async {
        var response: Result<Pairing, PairingError> = .failure(.codeExpiredOrUsed)
        let enrollment = ComputerLinkEnrollment(fetch: { _ in response }, store: { _ in true })
        await enrollment.connect(link())
        XCTAssertEqual(enrollment.phase, .expired)
        XCTAssertNotNil(enrollment.message)
        response = .failure(.unreachable)
        await enrollment.connect(link())
        XCTAssertEqual(enrollment.phase, .unavailable)
        XCTAssertNotNil(enrollment.message)
        response = .success(computer())
        await enrollment.connect(link())
        XCTAssertEqual(enrollment.phase, .saved)
    }

    func testUnsafeRelayAndDuplicateConnectDoNotFetchAgain() async {
        var fetches = 0
        var enrollment: ComputerLinkEnrollment!
        enrollment = ComputerLinkEnrollment(fetch: { _ in
            fetches += 1
            await enrollment.connect(self.link())
            return .failure(.badCode)
        }, store: { _ in true })
        await enrollment.connect(link().replacingOccurrences(of: "wss://relay.granttap.com", with: "http://public.example"))
        XCTAssertEqual(fetches, 0)
        await enrollment.connect(link())
        XCTAssertEqual(fetches, 1)
        XCTAssertEqual(enrollment.phase, .invalidLink)
    }

    func testPhoneNetworkLinkAddsAllComputersAsOneSave() async {
        let first = computer()
        var second = computer()
        second.room = String(repeating: "c", count: 32)
        var saved: [Pairing] = []
        let enrollment = ComputerLinkEnrollment(networkFetch: { _ in [first, second] },
            store: { _ in XCTFail("Network link must not save one computer at a time"); return false },
            storeNetwork: { saved = $0; return true })
        await enrollment.connect(link().replacingOccurrences(of: "pair-v2?v=2", with: "controllers?v=1"))
        XCTAssertEqual(saved, [first, second])
        XCTAssertEqual(enrollment.phase, .saved)
        XCTAssertEqual(enrollment.addedComputers, 2)
        XCTAssertNotNil(enrollment.message)
    }

    func testInvalidNetworkAndPartialFetchNeverSaveAnyComputer() async {
        var saved = false
        var invite = computer()
        invite.hub = true
        let rejected = ComputerLinkEnrollment(networkFetch: { _ in [invite] }, store: { _ in false },
                                               storeNetwork: { _ in saved = true; return true })
        let networkLink = link().replacingOccurrences(of: "pair-v2?v=2", with: "controllers?v=1")
        await rejected.connect(networkLink)
        XCTAssertEqual(rejected.phase, .wrongPurpose)
        XCTAssertFalse(saved)
        let incomplete = ComputerLinkEnrollment(networkFetch: { _ in
            throw ControllerNetworkTransfer.TransferError.incomplete
        }, store: { _ in false }, storeNetwork: { _ in saved = true; return true })
        await incomplete.connect(networkLink)
        XCTAssertEqual(incomplete.phase, .expired)
        XCTAssertFalse(saved)
    }

    private func link() -> String {
        "granttap://pair-v2?v=2&u=wss://relay.granttap.com&m=\(String(repeating: "a", count: 32))&k=\(String(repeating: "A", count: 43))"
    }

    private func computer() -> Pairing {
        let key = Data(repeating: 9, count: 32).base64EncodedString()
        return Pairing(relayUrl: "wss://relay.granttap.com", room: String(repeating: "b", count: 32),
                       role: "phone", deviceName: "Test PC", senderId: "test-controller",
                       myPublicKey: key, mySecretKey: key, peerPublicKey: key)
    }
}
