import SwiftUI
import XCTest
@testable import GrantTap

/// Every number on the Project page opens: a computer to what it did, a tool
/// to its calls, a call to the chat at the moment it happened.
@MainActor
final class ProjectUsageDrillInTests: XCTestCase {
    private let room = "drill-room"

    override func setUp() {
        super.setUp()
        CapabilityUsageStore.shared.clear()
    }

    override func tearDown() {
        CapabilityUsageStore.shared.clear()
        super.tearDown()
    }

    private func pairing(room: String) -> Pairing {
        Pairing(
            relayUrl: "ws://127.0.0.1:1", room: room, role: "phone",
            deviceName: "Studio", senderId: "drill",
            myPublicKey: "public", mySecretKey: "secret", peerPublicKey: "peer"
        )
    }

    private func execution(_ sessionId: String, computer: String) -> ExecutionSessionLink {
        ExecutionSessionLink(
            taskId: "task", sessionId: sessionId, provider: "claude",
            computerId: computer, workspace: "/repo", startedAt: 1
        )
    }

    private func snapshot(_ executions: [ExecutionSessionLink]) -> ProjectMeshSnapshot {
        .init(
            type: "mesh.snapshot", sessionId: "project", projectId: "project",
            project: .init(projectId: "project", name: "GrantTap", repositoryRoot: "/repo",
                           canonicalRepositoryId: "repo", createdAt: 1),
            tasks: [], executions: executions, claims: [], dependencies: [], events: [],
            generatedAt: Date().timeIntervalSince1970 * 1_000
        )
    }

    private func model() -> AppModel {
        let model = AppModel()
        var registry = ConnectionRegistryLogic.upsert(.empty, pairing: pairing(room: room))
        registry = ConnectionRegistryLogic.noteCatalog(
            registry, roomId: room,
            generatedAt: Date().timeIntervalSince1970 * 1_000, machineName: "Studio"
        )
        model.connectionRegistry = registry
        model.sessions = [
            SessionInfo(sessionId: "s1", agent: "claude", title: "Pairing", state: "working",
                        startedAt: 1, lastActivityAt: 2, tokensSession: 1_200, tokensLastTurn: 0),
            SessionInfo(sessionId: "s2", agent: "claude", title: "Docs", state: "idle",
                        startedAt: 1, lastActivityAt: 2, tokensSession: 300, tokensLastTurn: 0),
        ]
        return model
    }

    /// Recorded just after the store was cleared — anything older is dropped —
    /// and the clock is let past them so "the last 24 hours" contains them.
    private func seed() {
        let now = Date().timeIntervalSince1970 * 1_000 + 150
        defer { Thread.sleep(forTimeInterval: 0.35) }
        CapabilityUsageStore.shared.record(
            .cli, name: "Bash", sessionId: "s1", sourceId: "call-1", createdAt: now,
            commandPreview: "npm test", durationMs: 900, outcome: .success,
            sourceNamespace: room,
            resource: CapabilityResourceUsage(attribution: .attributed, cpuTimeMs: 400, peakRssBytes: 900)
        )
        CapabilityUsageStore.shared.record(
            .mcp, name: "github", sessionId: "s1", sourceId: "call-2", createdAt: now + 10,
            durationMs: 200, outcome: .error, sourceNamespace: room
        )
        CapabilityUsageStore.shared.record(
            .cli, name: "Bash", sessionId: "s2", sourceId: "call-3", createdAt: now + 20,
            durationMs: 100, outcome: .success, sourceNamespace: room,
            resource: CapabilityResourceUsage(attribution: .attributed, cpuTimeMs: 50, peakRssBytes: 50)
        )
        // A call recorded without a chat stays a plain row rather than a link.
        CapabilityUsageStore.shared.record(
            .skill, name: "review", sessionId: "s2", sourceId: "call-4", createdAt: now + 30
        )
    }

    func testTheProjectPageSumsAndOpensEverything() {
        let model = model()
        let mesh = snapshot([execution("s1", computer: "studio"), execution("s2", computer: "air")])

        // Nothing observed: the page still stands, without the usage sections.
        RenderProbe.render(NavigationView { ProjectMeshStatusView(snapshot: mesh, model: model) })

        seed()
        let ids = ProjectUsageStats.sessionIds(mesh)
        // Tokens add up across the chats a Project holds, each counted once.
        XCTAssertEqual(ProjectUsageStats.tokens(model.sessions + model.sessions, sessionIds: ids), 1_500)
        XCTAssertEqual(ProjectUsageStats.tokens(model.sessions, sessionIds: ["s2"]), 300)
        RenderProbe.render(NavigationView { ProjectMeshStatusView(snapshot: mesh, model: model) })

        // A computer's own page is scoped to the chats it ran here.
        let studio = ProjectComputerUsageView(endpointId: "studio", snapshot: mesh, model: model)
        XCTAssertEqual(studio.sessionIds, ["s1"])
        RenderProbe.render(NavigationView { studio.environmentObject(model) })
        let nowhere = ProjectComputerUsageView(endpointId: "ghost", snapshot: mesh, model: model)
        XCTAssertTrue(nowhere.sessionIds.isEmpty)
        RenderProbe.render(NavigationView { nowhere.environmentObject(model) })
    }

    func testTheCallListIsScopedToTheChatsItWasOpenedFrom() {
        let model = model()
        seed()
        let scoped = CapabilityUsageHistoryView(
            kind: .cli, name: "Bash", agent: nil, modelName: nil, sessionIds: ["s1"],
            appModel: model
        )
        let all = CapabilityUsageHistoryView(
            kind: .cli, name: "Bash", agent: nil, modelName: nil, appModel: model
        )
        let bash = CapabilityUsageStore.shared.events.filter { $0.kind == .cli }
        XCTAssertEqual(bash.filter(scoped.matches).map(\.sessionId), ["s1"])
        XCTAssertEqual(bash.filter(all.matches).count, 2, "the Usage tab passes no scope and sees every call")
        RenderProbe.render(NavigationView { scoped.environmentObject(model) })
    }

    func testTaskToolsAndCallsLeadSomewhere() {
        let model = model()
        seed()
        RenderProbe.render(
            NavigationView { TaskUsageHistoryView(sessionIds: ["s1", "s2"]) }
                .environmentObject(model)
        )
        // Both rows: one call can open its chat, one cannot.
        let events = CapabilityUsageStore.shared.events
        let linked = events.first { $0.kind == .cli }
        let plain = events.first { $0.kind == .skill }
        XCTAssertNotNil(linked); XCTAssertNotNil(plain)
        XCTAssertNotNil(linked.flatMap { CapabilityChatLink.target(for: $0, model: model) })
        XCTAssertNil(plain.flatMap { CapabilityChatLink.target(for: $0, model: model) })
        RenderProbe.render(
            NavigationView {
                List {
                    if let linked { UsageCallLink(event: linked) }
                    if let plain { UsageCallLink(event: plain) }
                }
            }
            .environmentObject(model)
        )
    }

    func testTheUsageTabDrawsWhenThePeriodWasBusy() {
        let model = model()
        seed()
        RenderProbe.render(NavigationView { CapabilityUsageView() }.environmentObject(model))
    }
}
