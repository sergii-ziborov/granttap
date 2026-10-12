import SwiftUI
import UIKit
import XCTest
@testable import GrantTap

/// A report the person sends themselves, carrying nothing they did not see.
@MainActor
final class BugReportTests: XCTestCase {
    private func report() -> DiagnosticsReport {
        DiagnosticsReport(
            appVersion: "1.0.0", build: "54", systemVersion: "18.2",
            deviceModel: "iPhone", locale: "ru_IL", linkedComputers: 2,
            connection: "Live", liveSessions: 3, governedProjects: 1
        )
    }

    func testTheReportCarriesTheShapeOfTheInstall() {
        let text = report().text
        XCTAssertTrue(text.contains("GrantTap 1.0.0 (54)"))
        XCTAssertTrue(text.contains("Linked computers: 2"))
        XCTAssertTrue(text.contains("Live tasks: 3"))
        XCTAssertTrue(text.contains("Mesh spaces reporting policy: 1"))
    }

    func testTheReportCarriesNothingSecret() {
        // Redaction is asserted rather than assumed: this is the whole reason
        // the report is built in one place instead of assembled at the sheet.
        XCTAssertFalse(DiagnosticsReport.containsSecret(report().text))
        // The guard itself must actually catch the things it names.
        XCTAssertTrue(DiagnosticsReport.containsSecret("pairing key: abc"))
        XCTAssertTrue(DiagnosticsReport.containsSecret("apns token"))
        XCTAssertTrue(
            DiagnosticsReport.containsSecret("YWJjZGVmZ2hpamtsbW5vcHFyc3R1dnd4eXoxMjM0"),
            "a run long enough to be key material has no business in a report"
        )
    }

    func testNothingIsSendableUntilSomethingIsDescribed() {
        let model = AppModel()
        var view = BugReportView(model: model)
        XCTAssertFalse(view.canSend, "an empty report says nothing and sends nothing")
        // The composed text is what the share sheet receives, and it is shown
        // on screen first, so it must match what the toggles say.
        view = BugReportView(model: model)
        RenderProbe.render(NavigationView { view })
    }

    func testTheScreenRendersWithAndWithoutDiagnostics() {
        let model = AppModel()
        RenderProbe.render(NavigationView { BugReportView(model: model) })

        // Described, with diagnostics off: the report is only the person's words.
        let written = BugReportView(
            model: model, description: "Chat opened at the top", includeDiagnostics: false
        )
        XCTAssertTrue(written.canSend)
        XCTAssertEqual(written.composed, "Chat opened at the top")
        RenderProbe.render(NavigationView { written })

        // With a screenshot and diagnostics: both travel, and the text still
        // carries nothing secret.
        let shot = UIGraphicsImageRenderer(size: CGSize(width: 8, height: 8)).image { context in
            UIColor.systemBlue.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 8, height: 8))
        }
        let full = BugReportView(model: model, description: "Broken", screenshot: shot)
        XCTAssertTrue(full.composed.contains("Broken"))
        XCTAssertTrue(full.composed.contains("GrantTap"))
        XCTAssertFalse(DiagnosticsReport.containsSecret(full.composed))
        RenderProbe.render(NavigationView { full })

        // The share sheet is a system controller; building it is enough to know
        // the items it would carry are well formed.
        XCTAssertEqual(ReportShareSheet(items: ["report text"]).items.count, 1)
    }

    func testAnOpaqueServerIdReadsAsAnIdRatherThanAName() {
        // Title-casing a UUID produced something longer and no more readable.
        let uuid = MCPIdentity(name: "4e69538b-cf6e-4c6c-9471-9cf5e6125442")
        XCTAssertTrue(uuid.isOpaqueIdentifier)
        XCTAssertEqual(uuid.displayName, "MCP 4e69538b")
        // A name someone chose is still title-cased as before.
        XCTAssertFalse(MCPIdentity(name: "github").isOpaqueIdentifier)
        XCTAssertEqual(MCPIdentity(name: "github").displayName, "GitHub")
        XCTAssertEqual(MCPIdentity(name: "file-system").displayName, "File System")
    }

    func testTheModelDescribesItselfWithoutIdentifiers() {
        let built = AppModel().diagnosticsReport()
        XCTAssertFalse(built.appVersion.isEmpty)
        XCTAssertFalse(built.build.isEmpty)
        XCTAssertFalse(DiagnosticsReport.containsSecret(built.text))
    }

    func testRequestedDiagnosticsRemainWritableAfterAChatGrant() throws {
        let oldEnvironment = ProcessInfo.processInfo.environment["GRANTTAP_TEST_DIAGNOSTICS"]
        setenv("GRANTTAP_TEST_DIAGNOSTICS", "1", 1)
        defer {
            if let oldEnvironment { setenv("GRANTTAP_TEST_DIAGNOSTICS", oldEnvironment, 1) }
            else { unsetenv("GRANTTAP_TEST_DIAGNOSTICS") }
        }
        let report = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("GrantTapConnectionDiagnostics.txt")
        let previous = try? Data(contentsOf: report)
        defer {
            if let previous { try? previous.write(to: report) }
            else { try? FileManager.default.removeItem(at: report) }
        }
        let model = AppModel()
        let client = RelayClient(pairing: PairingFixture.pairing(room: "diagnostics"))
        client.wireDiagnosticCounts = ["grant-saved": 1, "scoped-opened": 1]
        model.relaysByRoom[client.pairing.room] = client
        model.saveRequestedDiagnostics()
        let written = try String(contentsOf: report, encoding: .utf8)
        XCTAssertTrue(written.contains("grant-saved"))
        XCTAssertFalse(DiagnosticsReport.containsSecret(written))
    }

    func testReadinessRequiresCurrentCatalogAndEveryCurrentHistoryHead() {
        let model = AppModel()
        model.sessions = []
        model.activities = [:]
        XCTAssertEqual(model.nowReplicaTestStatus, "waiting")
        let now = Date().timeIntervalSince1970 * 1_000
        let chat = SessionInfo(sessionId: "readiness", agent: "codex", state: "working",
            startedAt: now - 10, lastActivityAt: now, tokensSession: 0, tokensLastTurn: 0)
        model.sessions = [chat]
        model.lastSessionsGeneratedAt = now
        XCTAssertEqual(model.nowReplicaTestStatus, "waiting")
        model.activities = [chat.sessionId: .init(sessionId: chat.sessionId, agent: "codex",
            state: "working", entries: [], generatedAt: now - 1, history: .init(hasMore: false))]
        XCTAssertEqual(model.nowReplicaTestStatus, "waiting")
        model.activities = [chat.sessionId: .init(sessionId: chat.sessionId, agent: "codex",
            state: "working", entries: [], generatedAt: now, history: .init(hasMore: false))]
        XCTAssertEqual(model.nowReplicaTestStatus, "ready")
        model.lastSessionsGeneratedAt = now - 100_000
        XCTAssertEqual(model.nowReplicaTestStatus, "waiting")
    }
}
