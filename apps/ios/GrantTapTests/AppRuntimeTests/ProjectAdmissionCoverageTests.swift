import XCTest
@testable import GrantTap

extension AppRuntimeTests {
    /// Admitting a computer is the one path that actually hands over the mesh
    /// key, so it is exercised with real relays rather than only its guards.
    @MainActor
    func testAdmittingAComputerGrantsTheProjectKeyAndKeepsForwarding() {
        let model = AppModel()
        // Session keys live in the Keychain under the room name, so a fixed room
        // carries a key over from the previous run of this very test.
        let run = UUID().uuidString
        let holder = "admit-holder-\(run)"
        let joiner = "admit-joiner-\(run)"
        addTeardownBlock {
            SessionKeyVault.remove(room: holder)
            SessionKeyVault.remove(room: joiner)
        }

        var registry = ConnectionRegistryLogic.upsert(.empty, pairing: testPairing(room: holder))
        registry = ConnectionRegistryLogic.upsert(registry, pairing: testPairing(room: joiner))
        model.connectionRegistry = registry
        let source = RelayClient(pairing: testPairing(room: holder))
        model.relaysByRoom[holder] = source
        model.relaysByRoom[joiner] = RelayClient(pairing: testPairing(room: joiner))

        let projectId = "admit-project-\(run)"
        model.meshSnapshots[projectId] = ProjectMeshSnapshot(
            type: "mesh.snapshot", sessionId: projectId, projectId: projectId,
            project: .init(projectId: projectId, name: "Admit", repositoryRoot: "/repo",
                           canonicalRepositoryId: "repo", createdAt: 1),
            tasks: [], executions: [], claims: [], dependencies: [], events: [], generatedAt: 1
        )
        model.meshProjectSourceRooms[projectId] = [holder]

        // Without a key on the holder there is nothing to copy, so admission is
        // refused rather than half-granting.
        XCTAssertFalse(model.admitComputerToProject(projectId: projectId, room: joiner))
        XCTAssertEqual(model.meshProjectSourceRooms[projectId], [holder])

        let key = Data(repeating: 7, count: 32).base64EncodedString()
        XCTAssertTrue(source.installForwardedScopeKey(key, scopeId: projectId))
        XCTAssertTrue(model.admitComputerToProject(projectId: projectId, room: joiner))

        // The joiner now takes part, so every later Project forward reaches it.
        XCTAssertEqual(model.meshProjectSourceRooms[projectId], [holder, joiner])
        // Admitting twice is refused: it already holds the key.
        XCTAssertFalse(model.admitComputerToProject(projectId: projectId, room: joiner))
    }

    @MainActor
    func testAdmissionStopsWhenTheMeshIsOffOrTheProjectIsUnknown() {
        let model = AppModel()
        let run = UUID().uuidString
        let holder = "admit-off-holder-\(run)"
        let joiner = "admit-off-joiner-\(run)"
        addTeardownBlock {
            SessionKeyVault.remove(room: holder)
            SessionKeyVault.remove(room: joiner)
        }
        var registry = ConnectionRegistryLogic.upsert(.empty, pairing: testPairing(room: holder))
        registry = ConnectionRegistryLogic.upsert(registry, pairing: testPairing(room: joiner))
        model.connectionRegistry = registry
        model.relaysByRoom[holder] = RelayClient(pairing: testPairing(room: holder))
        model.relaysByRoom[joiner] = RelayClient(pairing: testPairing(room: joiner))
        model.meshProjectSourceRooms["ghost-\(run)"] = [holder]

        // A Project with no snapshot has nothing to forward.
        XCTAssertFalse(model.admitComputerToProject(projectId: "ghost-\(run)", room: joiner))

        model.agentMeshPreferences.meshEnabled = false
        XCTAssertFalse(model.admitComputerToProject(projectId: "ghost-\(run)", room: joiner))
    }

    /// Scanning a code pairs a computer and puts it in the Project in one action.
    @MainActor
    func testPairingFromAProjectAdmitsOnlyTheComputerItJustAdded() {
        let model = AppModel()
        let run = UUID().uuidString
        let holder = "paired-holder-\(run)"
        let joiner = "paired-joiner-\(run)"
        addTeardownBlock {
            SessionKeyVault.remove(room: holder)
            SessionKeyVault.remove(room: joiner)
        }
        let projectId = "paired-project-\(run)"

        var registry = ConnectionRegistryLogic.upsert(.empty, pairing: testPairing(room: holder))
        model.connectionRegistry = registry
        let source = RelayClient(pairing: testPairing(room: holder))
        model.relaysByRoom[holder] = source
        model.meshSnapshots[projectId] = ProjectMeshSnapshot(
            type: "mesh.snapshot", sessionId: projectId, projectId: projectId,
            project: .init(projectId: projectId, name: "Paired", repositoryRoot: "/repo",
                           canonicalRepositoryId: "repo", createdAt: 1),
            tasks: [], executions: [], claims: [], dependencies: [], events: [], generatedAt: 1
        )
        model.meshProjectSourceRooms[projectId] = [holder]
        XCTAssertTrue(source.installForwardedScopeKey(
            Data(repeating: 3, count: 32).base64EncodedString(), scopeId: projectId
        ))

        let before = Set(model.connectionRegistry.connections.map(\.id))
        // The sheet dismissed without pairing anything.
        XCTAssertEqual(
            model.admitNewlyPairedComputers(projectId: projectId, pairedBefore: before), []
        )

        // Now a scan adds a computer, and only that one is admitted.
        registry = ConnectionRegistryLogic.upsert(registry, pairing: testPairing(room: joiner))
        model.connectionRegistry = registry
        model.relaysByRoom[joiner] = RelayClient(pairing: testPairing(room: joiner))
        XCTAssertEqual(
            model.admitNewlyPairedComputers(projectId: projectId, pairedBefore: before), [joiner]
        )
        XCTAssertEqual(model.meshProjectSourceRooms[projectId], [holder, joiner])
    }
}
