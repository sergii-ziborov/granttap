import XCTest
import TweetNacl
@testable import GrantTap

final class RepositorySnapshotContractTests: XCTestCase {
    private func snapshot() -> ProjectMeshSnapshot {
        .init(type: "mesh.snapshot", sessionId: "mesh", projectId: "mesh", publisherEndpointId: "mac",
            project: .init(projectId: "mesh", name: "Fixture", canonicalRepositoryId: "repo", createdAt: 1),
            repositoryGraphs: [.init(projectId: "mesh", repositoryId: "repo", revision: "content",
                weavatrixVersion: "2.17.4", analysisStatus: "INCOMPLETE", nodes: [], relations: [],
                totalNodes: 1, totalRelations: 0, truncated: false)],
            tasks: [], executions: [], claims: [], dependencies: [], events: [], generatedAt: 10)
    }

    private func details() -> ProjectRepositoryDetails {
        .init(projectId: "mesh", repositoryId: "repo", canonicalRepositoryId: "github.com/example/repo",
            endpointId: "mac", status: "ready", branch: "main", revision: String(repeating: "a", count: 40),
            dirty: false, commitCount: 1,
            commits: [.init(sha: String(repeating: "a", count: 40), subject: "Synthetic commit",
                author: "Fixture", committedAt: 1)], contributors: [.init(name: "Fixture", commits: 1)],
            contributorCount: 1, observedAt: 10)
    }

    func testEnrichedSnapshotReachesItsWaitingBuildWithGitFactsAndPreservesTheGraph() throws {
        var value = snapshot()
        let request = ProjectGraphRequest(createdAt: 9)
        value.graphAnalysisRequestId = request.requestId
        value.repositoryDetails = [details()]
        let data = try JSONEncoder().encode(value)
        XCTAssertTrue(ProjectMeshWireValidator.validSnapshot(data),
            "Git observations sent alongside architecture must not discard the whole build response.")
        let decoded = try JSONDecoder().decode(ProjectMeshSnapshot.self, from: data)
        XCTAssertEqual(decoded.repositoryDetails, value.repositoryDetails)
        XCTAssertEqual(decoded.repositoryGraphs, value.repositoryGraphs)
        XCTAssertEqual(request.receiving(decoded).result, .completed)
        XCTAssertFalse(request.receiving(decoded).pending)
        value.repositoryDetails = []
        XCTAssertTrue(ProjectMeshWireValidator.validSnapshot(try JSONEncoder().encode(value)))
        value.repositoryDetails = nil
        XCTAssertTrue(ProjectMeshWireValidator.validSnapshot(try JSONEncoder().encode(value)))
    }

    func testGitFactsRejectForeignScopeDuplicateReportsAndOversizedOrInvalidMetadata() throws {
        var value = snapshot()
        value.repositoryDetails = [details()]
        let encoded = try JSONEncoder().encode(value)
        let original = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        let report = try XCTUnwrap((original["repositoryDetails"] as? [[String: Any]])?.first)
        let changes: [(String, Any)] = [
            ("projectId", "foreign"), ("endpointId", "other-computer"), ("repositoryId", ""),
            ("canonicalRepositoryId", ""), ("status", "invented"), ("branch", String(repeating: "x", count: 513)),
            ("revision", String(repeating: "a", count: 65)), ("observedAt", -1), ("commitCount", -1),
            ("contributorCount", -1), ("commits", Array(repeating: report["commits"] as? [Any] ?? [], count: 9).flatMap { $0 }),
            ("contributors", Array(repeating: ["name": "Fixture", "commits": 1], count: 13)),
            ("commits", [["sha": "invalid", "subject": "Fixture", "author": "Fixture", "committedAt": 1]]),
            ("commits", [["sha": String(repeating: "a", count: 40), "subject": String(repeating: "x", count: 241),
                          "author": "Fixture", "committedAt": 1]]),
            ("commits", [["sha": String(repeating: "a", count: 40), "subject": "Fixture",
                          "author": String(repeating: "x", count: 161), "committedAt": 1]]),
            ("commits", [["sha": String(repeating: "a", count: 40), "subject": "Fixture",
                          "author": "Fixture", "committedAt": -1]]),
            ("contributors", [["name": "Fixture", "commits": -1]]),
            ("contributors", [["name": String(repeating: "x", count: 161), "commits": 1]]),
        ]
        for (key, replacement) in changes {
            var malformed = report
            malformed[key] = replacement
            var object = original
            object["repositoryDetails"] = [malformed]
            XCTAssertFalse(ProjectMeshWireValidator.validSnapshot(try JSONSerialization.data(withJSONObject: object)), key)
        }
        for count in [2, 65] {
            var object = original
            object["repositoryDetails"] = Array(repeating: report, count: count)
            XCTAssertFalse(ProjectMeshWireValidator.validSnapshot(try JSONSerialization.data(withJSONObject: object)))
        }
    }

    func testMergedReportsMayContainDistinctComputersWithinTheSameProject() throws {
        var value = snapshot()
        value.publisherEndpointId = nil
        value.repositoryDetails = [details(), .init(projectId: "mesh", repositoryId: "repo",
            endpointId: "remote", status: "unavailable", observedAt: 10)]
        XCTAssertTrue(ProjectMeshWireValidator.validSnapshot(try JSONEncoder().encode(value)))
    }

    @MainActor
    func testEncryptedBuildReplyUpdatesHealthAndFinishesItsExactPendingRequest() async throws {
        let archive = ProjectMeshPersistence.load()
        defer { ProjectMeshPersistence.save(archive) }
        let phone = try NaclBox.keyPair(), machine = try NaclBox.keyPair()
        let room = UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased()
        defer { SessionKeyVault.remove(room: room) }
        let pairing = Pairing(relayUrl: "wss://relay.test", room: room, role: "phone", deviceName: "Fixture",
            senderId: "phone", myPublicKey: phone.publicKey.base64EncodedString(),
            mySecretKey: phone.secretKey.base64EncodedString(), peerPublicKey: machine.publicKey.base64EncodedString())
        let client = RelayClient(pairing: pairing)
        let model = AppModel()
        model.demoMode = true
        model.meshSnapshots = [:]
        let request = ProjectGraphRequest(createdAt: 9)
        model.projectGraphRequests = ["mesh": request]
        let delivered = expectation(description: "authenticated graph report delivered")
        client.onMeshSnapshot = { value in
            model.receive(value, fromRoom: room)
            delivered.fulfill()
        }
        func receive<T: Encodable>(_ payload: T) throws {
            let sealed = try Crypto.seal(JSONEncoder().encode(payload), theirPublicKeyB64: pairing.myPublicKey,
                mySecretKeyB64: machine.secretKey.base64EncodedString())
            let envelope = Envelope(room: room, from: .machine, to: "phone", senderId: "machine",
                deliveryId: UUID().uuidString, nonce: sealed.nonce, box: sealed.box)
            client.handle(String(decoding: try JSONEncoder().encode(envelope), as: UTF8.self))
        }
        let key = Data(repeating: 1, count: 32).base64EncodedString().replacingOccurrences(of: "=", with: "")
        try receive(SessionKeyGrant(type: "session.key.grant", sessionId: "mesh", key: key,
            purpose: "project", createdAt: 9))
        var value = snapshot()
        value.graphAnalysisRequestId = request.requestId
        value.repositoryDetails = [details()]
        let inner = try XCTUnwrap(Crypto.openableSeal(JSONEncoder().encode(value), key: key))
        try receive(SessionSealed(type: "session.sealed", sessionId: "mesh",
            nonce: inner.nonce, box: inner.box, createdAt: 10))
        await fulfillment(of: [delivered], timeout: 3)
        XCTAssertEqual(model.meshSnapshots["mesh"]?.generatedAt, 10)
        XCTAssertEqual(model.meshSnapshots["mesh"]?.repositoryDetails, value.repositoryDetails)
        XCTAssertTrue(ProjectInsightReports.hasEvidence(try XCTUnwrap(model.meshSnapshots["mesh"])))
        XCTAssertEqual(model.projectGraphRequests["mesh"]?.result, .completed)
        XCTAssertEqual(model.projectGraphRequests["mesh"]?.pending, false)
    }
}
