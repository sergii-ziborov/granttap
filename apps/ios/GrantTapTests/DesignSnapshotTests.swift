import SwiftUI
import TweetNacl
import XCTest
@testable import GrantTap

/// The screens, drawn to disk.
///
/// A simulator nobody can tap still runs tests, so the screens that matter
/// are rendered here into PNG files for a person to look at — at the size of
/// an iPhone 16 Pro Max, which is what the store and the website show — only
/// when `GRANTTAP_SNAPSHOT_DIR` names where to put them. Without it this does
/// nothing but render each screen once, which is a check of its own.
@MainActor
final class DesignSnapshotTests: XCTestCase {
    private let now = Date().timeIntervalSince1970 * 1_000

    override func setUp() {
        super.setUp()
        ProjectMeshPersistence.clear()
    }

    override func tearDown() {
        MemberLinkStore.remove()
        ProjectMeshPersistence.clear()
        super.tearDown()
    }

    private func pairing(role: String, room: String, name: String, hub: Bool? = nil) throws -> Pairing {
        let me = try NaclBox.keyPair()
        let peer = try NaclBox.keyPair()
        return Pairing(relayUrl: "wss://relay.granttap.app", room: room, role: role, deviceName: name, senderId: "s",
                       myPublicKey: me.publicKey.base64EncodedString(), mySecretKey: me.secretKey.base64EncodedString(),
                       peerPublicKey: peer.publicKey.base64EncodedString(), hub: hub)
    }

    /// The demo phone, plus a Project shared with it by someone else and a
    /// person it shares its own Project with.
    private func demoModel() throws -> (AppModel, ownProject: String, sharedProject: String, link: MemberLink) {
        let model = AppModel()
        model.startDemo()
        model.agentMeshPreferences.meshEnabled = true
        let ownProject = try XCTUnwrap(model.meshSnapshots.keys.sorted().first)
        let hubRoom = String(repeating: "c", count: 32)
        let theirPhone = try pairing(role: "phone", room: hubRoom, name: "Olga's iPhone · Payments", hub: true)
        model.connectionRegistry = ConnectionRegistryLogic.upsert(model.connectionRegistry, pairing: theirPhone, mode: .add, prefer: false)
        let sharedProject = "shared-payments"
        model.meshSnapshots[sharedProject] = ProjectMeshSnapshot(
            type: "mesh.snapshot", sessionId: sharedProject, projectId: sharedProject,
            project: ProjectMeshProject(projectId: sharedProject, name: "Payments", repositoryRoot: "/repo/payments",
                                        canonicalRepositoryId: "github.com/example/payments", createdAt: now - 86_400_000),
            tasks: [ProjectMeshTask(taskId: "pay-1", projectId: sharedProject, title: "Refund webhooks", goal: "Handle refund webhooks",
                                    state: "working", ownerSessionId: "olga-chat", createdAt: now - 3_600_000, updatedAt: now - 60_000)],
            executions: [ExecutionSessionLink(taskId: "pay-1", sessionId: "olga-chat", provider: "codex", computerId: "Olga's Mac",
                                              workspace: "/repo/payments", startedAt: now - 3_600_000)],
            claims: [], dependencies: [], events: [], generatedAt: now
        )
        model.meshProjectSourceRooms[sharedProject] = [hubRoom]
        let linkRoom = String(repeating: "d", count: 32)
        let link = MemberLink(
            id: linkRoom, projectId: ownProject, name: "Olga", role: .member, rules: .preset(.member),
            createdAt: now - 600_000, inviteExpiresAt: now + 300_000, joinedAt: now - 500_000, lastSeenAt: now - 30_000,
            hubPairing: try pairing(role: "machine", room: linkRoom, name: "Hub")
        )
        model.memberLinks = [link]
        model.memberLinkConnected.insert(link.id)
        return (model, ownProject, sharedProject, link)
    }

    func testTheChangedScreensRenderAndAreKeptForALook() throws {
        let (model, ownProject, sharedProject, link) = try demoModel()
        let directory = ProcessInfo.processInfo.environment["GRANTTAP_SNAPSHOT_DIR"]
        let own = try XCTUnwrap(model.meshSnapshots[ownProject])
        let shared = try XCTUnwrap(model.meshSnapshots[sharedProject])
        let task = try XCTUnwrap(own.tasks.first { task in own.claims.contains { $0.taskId == task.taskId } } ?? own.tasks.first)
        let session = try XCTUnwrap(model.sessions.first { $0.projectId == ownProject } ?? model.sessions.first)
        let open: (SessionInfo) -> Void = { _ in }
        let screens: [(String, AnyView)] = [
            ("iphone-projects-shared", AnyView(NavigationView { ProjectsTabView(model: model) }.environmentObject(model))),
            ("iphone-join-project", AnyView(PairingSheet(purpose: .joinProject).environmentObject(model))),
            ("iphone-project-mesh", AnyView(NavigationView { ProjectMeshView(snapshot: own, model: model, onOpenSession: open) }.environmentObject(model))),
            ("iphone-members", AnyView(NavigationView { ProjectMembersView(snapshot: own, model: model) }.environmentObject(model))),
            ("iphone-members-shared", AnyView(NavigationView { ProjectMembersView(snapshot: shared, model: model) }.environmentObject(model))),
            ("iphone-invite", AnyView(MemberInviteSheet(projectId: ownProject, model: model).environmentObject(model))),
            ("iphone-member-detail", AnyView(NavigationView { MemberLinkDetailView(linkId: link.id, model: model) }.environmentObject(model))),
            ("iphone-task-route", AnyView(TaskRouteView(route: TaskRoute(projectId: ownProject, taskId: task.taskId), model: model, onOpenSession: open).environmentObject(model))),
            ("iphone-governance", AnyView(NavigationView { ProjectGovernanceView(project: own.project, model: model) }.environmentObject(model))),
            ("iphone-handoff", AnyView(TaskHandoffSheet(session: session, model: model).environmentObject(model))),
            ("iphone-report", AnyView(ReportExportSheet(report: model.report(for: .task(own, task))).environmentObject(model))),
        ]
        for (name, screen) in screens {
            let image = Self.render(screen)
            XCTAssertGreaterThan(image.pngData()?.count ?? 0, 8_000, name)
            if let directory {
                try FileManager.default.createDirectory(atPath: directory, withIntermediateDirectories: true)
                try XCTUnwrap(image.pngData()).write(to: URL(fileURLWithPath: directory).appendingPathComponent("\(name).png"))
            }
        }
    }

    /// A screen as an iPhone 16 Pro Max would show it: laid out in a key
    /// window in light style and drawn through the layer, which is what makes
    /// SwiftUI paint into the image, at three pixels per point.
    static func render<Content: View>(_ view: Content, size: CGSize = CGSize(width: 440, height: 956)) -> UIImage {
        let host = UIHostingController(rootView: view)
        let window = UIWindow(frame: CGRect(origin: .zero, size: size))
        window.overrideUserInterfaceStyle = .light
        window.rootViewController = host
        window.makeKeyAndVisible()
        host.view.setNeedsLayout()
        host.view.layoutIfNeeded()
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.6))
        let format = UIGraphicsImageRendererFormat()
        format.scale = 3
        let image = UIGraphicsImageRenderer(size: size, format: format).image { context in
            window.layer.render(in: context.cgContext)
        }
        window.isHidden = true
        window.rootViewController = nil
        return image
    }
}
