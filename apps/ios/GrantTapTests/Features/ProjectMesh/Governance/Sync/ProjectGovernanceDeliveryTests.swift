import XCTest
@testable import GrantTap

/// What becomes of a Governance edit after it is authored: what the phone
/// says while no computer has confirmed it, how it survives leaving the
/// screen, how it is queued for a computer that is not listening yet, and
/// what the outbox keeps.
@MainActor
final class ProjectGovernanceDeliveryTests: XCTestCase {
    private let now = ProjectGovernanceSyncFixtures.now

    func testFreshPairingRehydratesGovernanceAfterTheAppContainerWasWiped() throws {
        let model = AppModel()
        defer { ProjectGovernancePersistence.clear() }
        model.agentMeshPreferences = .defaults
        model.projectGovernance = [:]
        model.meshProjectSourceRooms = [:]
        let status = ProjectGovernanceSyncFixtures.policyStatus(
            endpoint: "mac", provider: "claude", status: .enforced
        )

        model.receive(status, fromRoom: "fresh-pairing-room")

        let restored = try XCTUnwrap(model.projectGovernance[status.projectId])
        XCTAssertEqual(restored.policy, status.policy)
        XCTAssertEqual(model.meshProjectSourceRooms[status.projectId], ["fresh-pairing-room"])
        XCTAssertEqual(
            ProjectGovernancePersistence.load()[status.projectId]?.policy,
            status.policy
        )
    }

    func testAppModelExplainsUnavailableAndUnconfirmedPolicyEdits() {
        let model = AppModel()
        model.projectGovernance = [:]
        XCTAssertFalse(model.applyProjectGovernance(
            projectId: "missing", enforcement: .strict, defaults: [:]
        ))
        XCTAssertNotNil(model.projectPolicyErrors["missing"])

        model.agentMeshPreferences.meshEnabled = true
        let status = ProjectGovernanceSyncFixtures.policyStatus(endpoint: "mac", provider: "claude", status: .enforced)
        model.projectGovernance["project"] = ProjectGovernanceLogic.merged(
            current: nil, status: status
        )
        XCTAssertFalse(model.applyProjectGovernance(
            projectId: "project", enforcement: .strict, defaults: [:]
        ))
        XCTAssertNotNil(model.projectPolicyErrors["project"])
        XCTAssertEqual(ProjectGovernanceLogic.defaultEffects(status.policy)[.mcp], .ask)
    }

    func testAnEditSurvivesLeavingTheScreenAndIsSavedWhenTheRelayTakesIt() throws {
        let model = AppModel()
        model.projectGovernance = [:]
        defer { ProjectGovernancePersistence.clear() }
        model.agentMeshPreferences.meshEnabled = true
        model.meshProjectSourceRooms["project"] = ["room-a"]
        model.relaysByRoom["room-a"] = RelayClient(pairing: ProjectGovernanceSyncFixtures.pairing(room: "room-a"))
        model.receive(ProjectGovernanceSyncFixtures.policyStatus(endpoint: "mac", provider: "claude", status: .enforced),
                      fromRoom: "room-a")

        XCTAssertTrue(model.applyProjectGovernance(
            projectId: "project", enforcement: .strict, defaults: [.shell: .deny]
        ))
        // Walking back one screen used to discard the edit, and it is kept
        // precisely while it has not been seen applied.
        let draft = try XCTUnwrap(model.projectPolicyDrafts["project"])
        XCTAssertEqual(draft.defaults[.shell], .deny)

        // While the packet is in flight Save is correctly closed. Once the
        // relay has answered, reopening the screen must show the edit rather
        // than the saved policy — if it reloaded the policy there would be
        // nothing to save, which is how the edit used to disappear.
        model.pendingProjectPolicyRevisions.removeValue(forKey: "project")
        let reopened = ProjectGovernanceView(
            project: ProjectGovernanceSyncFixtures.projectSnapshotProject(), model: model
        )
        XCTAssertTrue(reopened.canSave, "the edit is still there to be retried")

        // The computers say what they have applied through coverage. A saved
        // policy arriving retires the draft.
        model.deliveredProjectPolicyRevisions["project"] = 4
        var applied = ProjectGovernanceLogic.updatedPolicy(
            current: model.projectGovernance["project"]?.policy, projectId: "project",
            enforcement: .strict, defaults: [.shell: .deny], createdBy: "granttap-phone"
        )
        applied = ProjectPolicy(
            projectId: "project", revision: applied.revision,
            enforcement: .strict, rules: applied.rules
        )
        model.receive(ProjectGovernanceSyncFixtures.appliedStatus(applied), fromRoom: "room-a")
        XCTAssertNil(model.projectPolicyDrafts["project"], "an applied edit is no longer pending")
        XCTAssertNil(model.deliveredProjectPolicyRevisions["project"])
    }

    func testAProjectReportedWithNoPolicyCanStillBeGivenItsFirst() {
        let model = AppModel()
        defer { ProjectGovernancePersistence.clear() }
        model.agentMeshPreferences.meshEnabled = true
        model.meshProjectSourceRooms["project"] = ["room-a"]
        model.relaysByRoom["room-a"] = RelayClient(pairing: ProjectGovernanceSyncFixtures.pairing(room: "room-a"))
        // A computer that reported the Project but has no policy to report.
        model.projectGovernance["project"] = ProjectGovernanceProjection(
            projectId: "project", revision: 0, enforcement: .bestAvailable,
            rules: [], coverage: [], updatedAt: 1, policy: nil
        )
        XCTAssertTrue(
            model.applyProjectGovernance(
                projectId: "project", enforcement: .bestAvailable, defaults: [.mcp: .deny]
            ),
            "the Project with no policy is the one whose first policy must be writable"
        )
    }

    func testAppModelMergesCallbacksAndQueuesOneSetPerProjectComputer() throws {
        let model = AppModel()
        model.projectGovernance = [:]
        model.pendingProjectPolicyRevisions = [:]
        defer { ProjectGovernancePersistence.clear() }
        model.agentMeshPreferences.meshEnabled = true
        let rooms = ["room-a", "room-b"]
        model.meshProjectSourceRooms["project"] = Set(rooms)
        for room in rooms {
            model.relaysByRoom[room] = RelayClient(pairing: ProjectGovernanceSyncFixtures.pairing(room: room))
        }
        let status = ProjectGovernanceSyncFixtures.policyStatus(endpoint: "mac", provider: "claude", status: .enforced)
        model.receive(status, fromRoom: rooms[0])
        XCTAssertEqual(model.projectGovernance["project"]?.revision, 3)

        XCTAssertTrue(model.applyProjectGovernance(
            projectId: "project", enforcement: .strict, defaults: [.mcp: .ask]
        ))
        // Saving is settled by the relay, not by a computer's echo: waiting for
        // one left Save closed for good whenever none answered.
        XCTAssertNil(model.pendingProjectPolicyRevisions["project"])
        XCTAssertEqual(model.deliveredProjectPolicyRevisions["project"], 4)
        for room in rooms {
            let relay = try XCTUnwrap(model.relaysByRoom[room])
            let entry = try XCTUnwrap(relay.pendingSessionPayloads.values.first)
            let request = try JSONDecoder().decode(ProjectPolicySet.self, from: entry.plain)
            XCTAssertEqual(request.expectedRevision, 3)
            XCTAssertEqual(request.policy.revision, 4)
            relay.disconnect()
        }

        var acknowledged = status
        acknowledged.policy.revision = 4
        acknowledged.policy.rules = acknowledged.policy.rules.map {
            var rule = $0
            rule.revision = 4
            return rule
        }
        acknowledged.coverage.policyRevision = 4
        acknowledged.coverage.endpoints = acknowledged.coverage.endpoints.map {
            var value = $0
            value.policyRevision = 4
            return value
        }
        model.receive(acknowledged, fromRoom: rooms[0])
        XCTAssertNil(model.pendingProjectPolicyRevisions["project"])
    }

    func testGovernanceCacheIsSeparateBoundedAndRoundTripsFullPolicy() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let url = root.appendingPathComponent("project-governance-cache.json")
        defer { try? FileManager.default.removeItem(at: root) }
        var values: [String: ProjectGovernanceProjection] = [:]
        for index in 0..<70 {
            let status = ProjectGovernanceSyncFixtures.policyStatus(
                endpoint: "mac-\(index)", provider: "claude", status: .enforced,
                projectId: "project-\(index)"
            )
            values[status.projectId] = ProjectGovernanceLogic.merged(
                current: nil, status: status
            )
        }
        ProjectGovernancePersistence.save(values, to: url)
        let restored = ProjectGovernancePersistence.load(from: url)
        XCTAssertEqual(restored.count, 64)
        XCTAssertNotNil(restored.values.first?.policy)
        ProjectGovernancePersistence.clear(at: url)
        XCTAssertTrue(ProjectGovernancePersistence.load(from: url).isEmpty)
    }

    func testAPolicyIsHeldForARoomThatIsNotListeningYet() throws {
        let model = AppModel()
        defer {
            ProjectGovernancePersistence.clear()
            ProjectPolicyOutboxStore.clear()
        }
        model.projectPolicyOutbox = []
        model.agentMeshPreferences.meshEnabled = true
        // Two Project computers; only one of them is connected right now.
        model.meshProjectSourceRooms["project"] = ["room-up", "room-down"]
        model.relaysByRoom["room-up"] = RelayClient(pairing: ProjectGovernanceSyncFixtures.pairing(room: "room-up"))
        model.receive(ProjectGovernanceSyncFixtures.policyStatus(endpoint: "mac", provider: "claude", status: .enforced),
                      fromRoom: "room-up")

        XCTAssertTrue(model.applyProjectGovernance(
            projectId: "project", enforcement: .strict, defaults: [.shell: .deny]
        ))
        // The sleeping computer's copy is written down rather than skipped.
        let queued = model.projectPolicyOutbox.filter { $0.room == "room-down" }
        XCTAssertEqual(queued.count, 1)
        XCTAssertEqual(queued.first?.revision, 4)
        // Saving is not hostage to which machine is awake.
        XCTAssertEqual(model.deliveredProjectPolicyRevisions["project"], 4)
        XCTAssertNil(model.projectPolicyErrors["project"])

        // A newer edit supersedes the older one outright: delivering both in
        // order would leave that computer on the policy that was replaced.
        XCTAssertTrue(model.applyProjectGovernance(
            projectId: "project", enforcement: .strict, defaults: [.mcp: .deny]
        ))
        // Both edits target revision 4: nothing has confirmed the first, so the
        // second replaces it rather than queuing behind it.
        let held = model.projectPolicyOutbox.filter { $0.room == "room-down" }
        XCTAssertEqual(held.count, 1, "one entry per room, not one per attempt")
        XCTAssertEqual(held.first?.revision, 4)
        XCTAssertEqual(
            ProjectGovernanceLogic.defaultEffects(held.first?.request.policy)[.mcp], .deny,
            "the entry carries the newer edit"
        )
    }

    func testTheOutboxKeepsOnlyTheNewestUnexpiredEditPerRoom() {
        let now = 1_800_000_000_000.0
        func entry(_ room: String, _ revision: Int, at createdAt: Double)
        -> ProjectPolicyOutboxEntry {
            ProjectPolicyOutboxEntry(
                projectId: "project", revision: revision, room: room,
                request: ProjectPolicySet(
                    type: "project.policy.set", sessionId: "project", projectId: "project",
                    expectedRevision: revision - 1,
                    policy: ProjectPolicy(
                        projectId: "project", revision: revision, enforcement: .strict, rules: []
                    ),
                    createdAt: createdAt
                ),
                createdAt: createdAt
            )
        }
        let entries = [
            entry("a", 3, at: now - 1_000),
            entry("a", 5, at: now),
            entry("b", 2, at: now - ProjectPolicyOutboxStore.maxAgeMs - 1),
            entry("c", 7, at: now),
        ]
        let pending = ProjectPolicyOutboxLogic.pending(entries, at: now)
        // Newest per room; the day-old one is stale and asking again is honest.
        XCTAssertEqual(pending.map(\.room), ["a", "c"])
        XCTAssertEqual(pending.first?.revision, 5)

        // Delivering one settles it and everything it supersedes for that room.
        let settled = ProjectPolicyOutboxLogic.settled(entries, delivered: entry("a", 5, at: now))
        XCTAssertTrue(settled.allSatisfy { $0.room != "a" })
        XCTAssertEqual(settled.count, 2)

        XCTAssertEqual(
            ProjectPolicyOutboxLogic.entries(
                for: entry("a", 9, at: now).request, rooms: ["x", "y"], at: now
            ).map(\.room),
            ["x", "y"]
        )
    }
}
