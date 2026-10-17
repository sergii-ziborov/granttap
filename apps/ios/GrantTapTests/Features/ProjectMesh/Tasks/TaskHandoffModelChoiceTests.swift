import SwiftUI
import XCTest
@testable import GrantTap

/// The transfer sheet offers the models the destination computer reported,
/// by the same computer the transfer goes to, and says so when there are none.
@MainActor
final class TaskHandoffModelChoiceTests: XCTestCase {
    private let now = Date().timeIntervalSince1970 * 1_000

    override func setUp() {
        super.setUp()
        ProjectMeshPersistence.clear()
        AgentMeshPreferencesStore.save(.defaults)
    }

    override func tearDown() {
        ProjectMeshPersistence.clear()
        AgentMeshPreferencesStore.save(.defaults)
        super.tearDown()
    }

    private func session() -> SessionInfo {
        SessionInfo(sessionId: "chat", agent: "claude", projectId: "project", taskId: "task", title: "Move me",
                    cwd: "/repo", branch: "main", state: "idle", startedAt: now - 1_000, lastActivityAt: now,
                    tokensSession: 1, tokensLastTurn: 1)
    }

    private func row(_ id: String, provider: String, endpoint: String, efforts: [String]? = nil) -> ProjectAdvertisedModel {
        ProjectAdvertisedModel(modelId: id, provider: provider, endpointId: endpoint, source: "advertised",
                               label: id.uppercased(), priority: nil, supportedEfforts: efforts, observedAt: now - 1_000)
    }

    private func model(catalogs: [ProjectEndpointModelCatalog], integrations: [String: [AgentIntegrationInfo]] = [:],
                       published: [String: String] = [:]) -> AppModel {
        let model = AppModel()
        model.agentMeshPreferences = .defaults
        var snapshot = ProjectMeshSnapshot(
            type: "mesh.snapshot", sessionId: "project", projectId: "project",
            project: .init(projectId: "project", name: "nodvox", repositoryRoot: "/repo",
                           canonicalRepositoryId: "github.com/x/nodvox", createdAt: 1),
            tasks: [.init(taskId: "task", projectId: "project", title: "Move me", goal: "g", state: "working",
                          ownerSessionId: "chat", createdAt: 1, updatedAt: 2)],
            executions: [.init(taskId: "task", sessionId: "chat", provider: "claude", computerId: "source.lan",
                               workspace: "/repo", branch: "main", uncommitted: false, startedAt: 1)],
            claims: [], dependencies: [], events: [], generatedAt: now)
        snapshot.modelCatalog = catalogs
        model.meshSnapshots = ["project": snapshot]
        model.connectionRegistry = .init(connections: ["source", "target"].map {
            LinkedComputer(id: $0, pairing: PairingFixture.pairing(room: $0), label: $0.capitalized,
                           addedAt: now, lastCatalogAt: now, lastMachineName: "\($0).lan")
        }, preferredId: "source")
        model.sessionSourceRooms["chat"] = ["source"]
        model.agentIntegrationsByRoom = integrations
        model.meshComputerRoomByEndpointId = published
        return model
    }

    private func codex(_ endpoint: String, cloud: Bool? = nil) -> AgentIntegrationInfo {
        AgentIntegrationInfo(agent: "codex", installed: true, hookConfigured: true, endpointId: endpoint, cloud: cloud)
    }

    func testTheComputersOwnReportFindsItsModelsBeforeAnySnapshotArrives() {
        let catalog = ProjectEndpointModelCatalog(endpointId: "target.lan", observedAt: now, models: [
            row("gpt-6-sol", provider: "codex", endpoint: "target.lan", efforts: ["low", "high"]),
            row("grok-4.7", provider: "grok", endpoint: "target.lan", efforts: ["low", "medium", "high", "xhigh"]),
        ])
        // After a relaunch the snapshot map is empty; the status report is not.
        let model = model(catalogs: [catalog], integrations: ["target": [codex("target.lan")]])
        let sheet = TaskHandoffSheet(session: session(), model: model, initialTargetRoom: "target",
                                     initialTargetProvider: "codex")
        XCTAssertEqual(sheet.destinationComputer(for: "target"), "target.lan")
        XCTAssertEqual(sheet.modelOptions.map(\.id), ["gpt-6-sol"])
        XCTAssertNil(sheet.modelAvailabilityNote)
        XCTAssertEqual(sheet.effortChoices, TurnEffort.supported(by: "codex"), "Automatic model: every Codex level")
        let withModel = TaskHandoffSheet(session: session(), model: model, initialTargetRoom: "target",
                                         initialTargetProvider: "codex", initialTargetModel: "gpt-6-sol")
        XCTAssertEqual(withModel.effortChoices, [.low, .high], "a chosen model offers only its own levels")
        let grok = TaskHandoffSheet(session: session(), model: model, initialTargetRoom: "target",
                                    initialTargetProvider: "grok", initialTargetModel: "grok-4.7")
        XCTAssertEqual(grok.modelOptions.map(\.id), ["grok-4.7"])
        XCTAssertEqual(grok.effortChoices, [.low, .medium, .high, .xhigh])
        XCTAssertEqual(model.turnModelCatalog(agent: "codex", roomId: "target").options.map(\.id), ["gpt-6-sol"],
                       "the new-task composer reads the same computer")
        RenderProbe.render(sheet)
    }

    func testAnOldNameInTheSnapshotMapNoLongerHidesTheModels() {
        let fresh = ProjectEndpointModelCatalog(endpointId: "target-new", observedAt: now, models: [
            row("gpt-6-sol", provider: "codex", endpoint: "target-new")])
        let model = model(catalogs: [fresh], published: ["target-old": "target", "target-new": "target"])
        XCTAssertEqual(model.catalogEndpoint(forRoom: "target"), "target-new", "the computer with a current catalog")
        let sheet = TaskHandoffSheet(session: session(), model: model, initialTargetRoom: "target",
                                     initialTargetProvider: "codex")
        XCTAssertEqual(sheet.destinationComputer(for: "target"), "target-new", "the models shown are where it goes")
        XCTAssertEqual(sheet.modelOptions.map(\.id), ["gpt-6-sol"])
        model.meshComputerRoomByEndpointId = [:]
        model.sessions = [SessionInfo(sessionId: "other", agent: "codex", computerId: "target-new", state: "idle",
                                      startedAt: 1, lastActivityAt: 1, tokensSession: 0, tokensLastTurn: 0)]
        model.sessionSourceRooms["other"] = ["target"]
        XCTAssertEqual(model.catalogEndpoint(forRoom: "target"), "target-new", "its chats name it when nothing else does")
    }

    func testNoReportedModelsIsSaidAndAutomaticStaysTheChoice() {
        let model = model(catalogs: [], integrations: ["target": [codex("target.lan")]])
        let grok = TaskHandoffSheet(session: session(), model: model, initialTargetRoom: "target",
                                    initialTargetProvider: "grok")
        XCTAssertTrue(grok.modelOptions.isEmpty, "unknown stays unknown")
        XCTAssertEqual(grok.modelAvailabilityNote,
                       "Grok Build on this computer has not reported a model list. Automatic lets it choose its own model.")
        let unknownComputer = TaskHandoffSheet(session: session(), model: self.model(catalogs: []),
                                               initialTargetRoom: "target", initialTargetProvider: "codex")
        XCTAssertEqual(unknownComputer.modelAvailabilityNote,
                       "This computer has not reported its models yet. Automatic lets the provider choose.")
        let claude = TaskHandoffSheet(session: session(), model: model, initialTargetRoom: "target",
                                      initialTargetProvider: "claude")
        XCTAssertEqual(claude.modelOptions.map(\.id), ["opus", "sonnet", "haiku", "fable"], "Claude Code's own aliases")
        RenderProbe.render(grok)
    }

    func testTheChosenModelAndEffortRideWithTheFirstMessageOfTheTransfer() {
        let model = model(catalogs: [])
        let destination = "transfer-\(UUID().uuidString.lowercased())"
        model.rememberTransferChoice(destination: destination, model: "gpt-6-sol", effort: "xhigh")
        XCTAssertEqual(model.turnOverrides.chatOverrides(destination).model?.rawValue, "gpt-6-sol")
        XCTAssertEqual(model.turnOverrides.chatOverrides(destination).effort, .xhigh)
        let untouched = "transfer-\(UUID().uuidString.lowercased())"
        model.rememberTransferChoice(destination: untouched, model: "", effort: "")
        XCTAssertNil(model.turnOverrides.chatOverrides(untouched).model, "Automatic leaves the chat to its defaults")
        model.turnOverrides.setChatOverrides(.unchanged, for: destination)
    }

    func testCloudRunnersAppearOnlyUnderTheComputerHoldingTheTask() {
        let model = model(catalogs: [], integrations: [
            "source": [codex("source.lan", cloud: true),
                       AgentIntegrationInfo(agent: "claude", installed: true, hookConfigured: true, cloud: true)],
            "target": [codex("target.lan", cloud: true)],
        ])
        let sheet = TaskHandoffSheet(session: session(), model: model, initialTargetRoom: "source",
                                     initialTargetProvider: "codex")
        XCTAssertEqual(sheet.cloudTargets.map(\.tag), ["claude", "codex"].map {
            TaskHandoffCloudTarget(provider: $0, room: "source").tag })
        let claude = TaskHandoffSheet(session: session(), model: model,
            initialTargetRoom: TaskHandoffCloudTarget(provider: "claude", room: "source").tag,
            initialTargetProvider: "claude")
        XCTAssertFalse(claude.staysHere, "a cloud runner is never this computer, even for the same agent")
        XCTAssertFalse(claude.sameAgentHere)
        XCTAssertEqual(claude.destinationProvider, "claude")
        XCTAssertEqual(claude.destinationComputer(for: claude.targetRoom), "source.lan")
        XCTAssertEqual(claude.modelOptions.map(\.id), ["opus", "sonnet", "haiku", "fable"])
        XCTAssertTrue(claude.readinessChecks.contains { $0.id == "cloudBranch" && $0.warning })
        XCTAssertTrue(claude.isReady)
        XCTAssertEqual(claude.cloudLaunch, ProjectMeshCloudLaunch())
        let codexCloud = TaskHandoffSheet(session: session(), model: model,
            initialTargetRoom: TaskHandoffCloudTarget(provider: "codex", room: "source").tag,
            initialTargetProvider: "claude")
        XCTAssertEqual(codexCloud.destinationProvider, "codex")
        XCTAssertTrue(codexCloud.modelOptions.isEmpty, "Codex Cloud runs its environment's model")
        XCTAssertTrue(codexCloud.effortChoices.isEmpty)
        XCTAssertNil(codexCloud.modelAvailabilityNote)
        let other = TaskHandoffSheet(session: session(), model: self.model(catalogs: []), initialTargetRoom: "source")
        XCTAssertTrue(other.cloudTargets.isEmpty, "a computer that reports no cloud start offers none")
        RenderProbe.render(claude)
        RenderProbe.render(codexCloud)
    }

    func testACloudTransferWaitsForTheRecordedRunOrTheComputersRefusal() async {
        let model = model(catalogs: [], integrations: ["source": [codex("source.lan", cloud: true)]])
        let tag = TaskHandoffCloudTarget(provider: "codex", room: "source").tag
        let sheet = TaskHandoffSheet(session: session(), model: model, initialTargetRoom: tag)
        var snapshot = model.meshSnapshots["project"]!
        snapshot.executions.append(ExecutionSessionLink(taskId: "task", sessionId: "task_e_1", provider: "codex",
            computerId: "source.lan", workspace: "/repo", startedAt: now, endedAt: nil,
            external: ExternalExecution(runner: "codex_cloud", url: "https://chatgpt.com/codex/tasks/task_e_1")))
        model.meshSnapshots["project"] = snapshot
        await sheet.waitForHandoff(previousEvents: [], computer: "source.lan")
        XCTAssertEqual(CloudHandoffOutcome.observe(session: session(), snapshot: snapshot,
            target: TaskHandoffCloudTarget(provider: "codex", room: "source"), computer: "source.lan",
            previousEvents: [], notBefore: 0), .started(snapshot.executions.last!))

        snapshot.executions.removeLast()
        snapshot.events.append(ProjectMeshEvent(type: "mesh.event", sessionId: "task", eventId: "blocked",
            projectId: "project", taskId: "task", sourceSessionId: "chat", eventType: "TASK_BLOCKED",
            createdAt: now, payload: .init(reason: "Name the Codex Cloud environment")))
        model.meshSnapshots["project"] = snapshot
        await sheet.waitForHandoff(previousEvents: [], computer: "source.lan")
        XCTAssertNil(sheet.cloudRun, "a refusal records no run")
    }
}
