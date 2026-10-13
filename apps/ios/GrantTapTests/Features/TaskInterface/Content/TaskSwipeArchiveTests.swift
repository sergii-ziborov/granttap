import XCTest
import SwiftUI
import UIKit
@testable import GrantTap

@MainActor
final class TaskSwipeArchiveTests: XCTestCase {
    func testRevealedActionsRemainReadableInBothAppearances() throws {
        for style in [UIUserInterfaceStyle.light, .dark] {
            let image = renderActions(style)
            let attachment = XCTAttachment(image: image)
            attachment.name = style == .dark ? "Task swipe actions dark" : "Task swipe actions light"
            attachment.lifetime = .keepAlways
            add(attachment)
            let pixels = try imagePixels(image)
            for x in [254, 342] {
                let values = (48..<113).flatMap { y in
                    (x + 14..<x + 74).map { luminance(pixels, x: $0, y: y) }
                }
                let ratio = (try XCTUnwrap(values.max()) + 0.05) / (try XCTUnwrap(values.min()) + 0.05)
                XCTAssertGreaterThanOrEqual(ratio, 4.5, "Both action labels must remain readable.")
            }
            if style == .dark {
                XCTAssertLessThan(luminance(pixels, x: 298, y: 12), 0.2,
                                  "Revealing Send must not flash a white panel in dark appearance.")
            }
        }
    }

    func testArchivingATaskHidesEveryExecutionAndKeepsRestorableSnapshots() {
        let priorIds = UserDefaults.standard.object(forKey: "granttap.archived-sessions")
        let priorSnapshots = ArchivedSessionPersistence.load()
        defer {
            if let priorIds {
                UserDefaults.standard.set(priorIds, forKey: "granttap.archived-sessions")
            } else {
                UserDefaults.standard.removeObject(forKey: "granttap.archived-sessions")
            }
            ArchivedSessionPersistence.save(priorSnapshots)
        }

        let model = AppModel()
        model.archivedSessionIds = []
        model.archivedSessions = [:]
        let first = session("first")
        let second = session("second")
        model.sessions = [first, second]
        let item = TaskListItem(
            id: "task:project\u{1f}task", destination: .task(.init(projectId: "project", taskId: "task")),
            projectId: "project", taskId: "task", projectName: "Project", title: "Task",
            summary: nil, state: "working", ownerExecution: nil, currentSession: second,
            historicalExecutions: [], sessionIds: [first.sessionId, second.sessionId], lastActivityAt: 2
        )

        ContentView(modelOverride: model).archiveTask(item)

        XCTAssertTrue(model.isArchived(first.sessionId))
        XCTAssertTrue(model.isArchived(second.sessionId))
        XCTAssertEqual(Set(model.archivedSessions.keys), Set([first.sessionId, second.sessionId]))
        XCTAssertTrue(ArchivedSessionPersistence.load().keys.contains(first.sessionId))
    }

    func testTaskWithoutALiveExecutionStillRendersItsHistoryCard() {
        let model = AppModel()
        let route = TaskRoute(projectId: "project", taskId: "task")
        model.meshSnapshots["project"] = ProjectMeshSnapshot(
            type: "mesh.snapshot", sessionId: "project", projectId: "project",
            project: .init(projectId: "project", name: "Project", repositoryRoot: "/repo",
                           canonicalRepositoryId: "github.com/x/project", createdAt: 1),
            tasks: [.init(taskId: "task", projectId: "project", title: "Past task",
                          goal: "Last known work", state: "finished", createdAt: 1, updatedAt: 2)],
            executions: [], claims: [], dependencies: [], events: [], generatedAt: 2
        )
        let item = try! XCTUnwrap(TaskListCatalog.items(model: model, sessions: []).first)
        let content = ContentView(modelOverride: model)

        RenderProbe.render(content.taskActionCard(item))

        XCTAssertNil(item.currentSession)
        XCTAssertEqual(item.destination, .task(route))
    }

    private func session(_ id: String) -> SessionInfo {
        SessionInfo(sessionId: id, agent: "codex", title: id, cwd: "/repo",
                    state: "working", startedAt: 1, lastActivityAt: 2,
                    tokensSession: 0, tokensLastTurn: 0)
    }

    private func renderActions(_ style: UIUserInterfaceStyle) -> UIImage {
        let frame = CGRect(x: 0, y: 0, width: 430, height: 160)
        let view = TaskSwipeCard(id: "contrast-fixture", revealed: .constant("contrast-fixture"),
                                 open: {}, archive: {}, send: {}) {
            Text("Task").frame(maxWidth: .infinity, maxHeight: .infinity).background(Theme.raised)
        }.ignoresSafeArea().preferredColorScheme(style == .dark ? .dark : .light)
        let controller = UIHostingController(rootView: view)
        let window = UIWindow(frame: frame)
        window.overrideUserInterfaceStyle = style
        window.rootViewController = controller
        window.isHidden = false
        controller.view.frame = frame
        controller.view.layoutIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.1))
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let image = UIGraphicsImageRenderer(size: frame.size, format: format).image { _ in
            controller.view.drawHierarchy(in: frame, afterScreenUpdates: true)
        }
        window.isHidden = true
        return image
    }

    private func imagePixels(_ image: UIImage) throws -> [UInt8] {
        let cgImage = try XCTUnwrap(image.cgImage)
        var pixels = [UInt8](repeating: 0, count: 430 * 160 * 4)
        let context = try XCTUnwrap(CGContext(data: &pixels, width: 430, height: 160,
            bitsPerComponent: 8, bytesPerRow: 430 * 4, space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue))
        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: 430, height: 160))
        return pixels
    }

    private func luminance(_ pixels: [UInt8], x: Int, y: Int) -> Double {
        let at = (y * 430 + x) * 4
        let rgb = (0..<3).map { channel -> Double in
            let value = Double(pixels[at + channel]) / 255
            return value <= 0.04045 ? value / 12.92 : pow((value + 0.055) / 1.055, 2.4)
        }
        return rgb[0] * 0.2126 + rgb[1] * 0.7152 + rgb[2] * 0.0722
    }
}
