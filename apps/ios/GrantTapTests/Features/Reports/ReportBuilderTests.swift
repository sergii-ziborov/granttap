import PDFKit
import SwiftUI
import XCTest
@testable import GrantTap

@MainActor
final class ReportBuilderTests: XCTestCase {
    private let now = 1_800_000_000_000.0

    private func project() -> ProjectMeshProject {
        ProjectMeshProject(projectId: "p", name: "nodvox", repositoryRoot: "/Users/me/dev/nodvox",
                           canonicalRepositoryId: "github.com/sergii/nodvox", createdAt: 1)
    }

    private func snapshot() -> ProjectMeshSnapshot {
        var snapshot = ProjectMeshSnapshot(
            type: "mesh.snapshot", sessionId: "p", projectId: "p", project: project(),
            tasks: [
                ProjectMeshTask(taskId: "t1", projectId: "p", title: "Pause and resume", goal: "Add pause", state: "working",
                                ownerSessionId: "s1", createdAt: now - 7_200_000, updatedAt: now - 60_000),
                ProjectMeshTask(taskId: "t2", projectId: "p", title: "Reports", goal: "Export CSV", state: "completed",
                                ownerSessionId: "s2", createdAt: now - 3_600_000, updatedAt: now - 1_800_000),
            ],
            executions: [
                ExecutionSessionLink(taskId: "t1", sessionId: "s1", provider: "claude", computerId: "Mac.lan",
                                     workspace: "/Users/me/dev/nodvox", branch: "main", activeAt: now - 60_000,
                                     startedAt: now - 7_200_000),
                ExecutionSessionLink(taskId: "t2", sessionId: "s2", provider: "codex", computerId: "Mac.lan",
                                     workspace: "/Users/me/dev/nodvox", branch: "feat/reports",
                                     startedAt: now - 3_600_000, endedAt: now - 1_800_000),
            ],
            claims: [], dependencies: [],
            events: [
                ProjectMeshEvent(type: "mesh.event", sessionId: "t1", eventId: "e1", projectId: "p", taskId: "t1",
                                 sourceSessionId: "s1", eventType: "TASK_BLOCKED", createdAt: now - 30_000,
                                 payload: .init(reason: "Handoff is not ready.", needsUser: true, failed: true)),
                ProjectMeshEvent(type: "mesh.event", sessionId: "t2", eventId: "e2", projectId: "p", taskId: "t2",
                                 sourceSessionId: "s2", eventType: "TASK_PROGRESS", createdAt: now - 20_000,
                                 payload: .init(summary: "Halfway")),
            ],
            generatedAt: now
        )
        snapshot.bindings = [
            ProjectBindingSummary(bindingId: "b1", projectId: "p", endpointId: "Mac.lan",
                                  repositoryId: "github.com/sergii/nodvox", displayName: "nodvox", available: true),
        ]
        return snapshot
    }

    private func session(_ id: String, agent: String, tokens: Int, taskId: String) -> SessionInfo {
        SessionInfo(sessionId: id, agent: agent, projectId: "p", taskId: taskId, computerId: "Mac.lan",
                    title: "Chat \(id)", cwd: "/Users/me/dev/nodvox", branch: "main", state: "idle",
                    startedAt: now - 7_200_000, lastActivityAt: now - 60_000, tokensSession: tokens, tokensLastTurn: 10)
    }

    private func event(_ id: String, kind: CapabilityUsageKind, name: String, session: String,
                       outcome: CapabilityOutcome = .success, cpu: Int? = nil, peak: Int? = nil,
                       at offset: Double = 0) -> CapabilityUsageEvent {
        CapabilityUsageEvent(
            id: id, sourceId: "src:\(id)", sourceRoom: "room", agent: "claude", model: nil, kind: kind, name: name,
            sessionId: session, createdAt: now - 3_600_000 + offset, toolName: kind == .cli ? "Bash" : name,
            commandPreview: kind == .cli ? "\(name) --version, quoted \"yes\"" : nil,
            durationMs: 120, outcome: outcome, errorClass: outcome == .error ? "exit 1" : nil,
            resource: cpu == nil && peak == nil ? nil : CapabilityResourceUsage(attribution: .measured, cpuTimeMs: cpu, peakRssBytes: peak)
        )
    }

    private func inputs() -> ReportInputs {
        var inputs = ReportInputs()
        inputs.now = Date(timeIntervalSince1970: now / 1_000)
        inputs.sessions = [session("s1", agent: "claude", tokens: 12_000, taskId: "t1"),
                           session("s2", agent: "codex", tokens: 3_000, taskId: "t2"),
                           session("s1", agent: "claude", tokens: 999, taskId: "t1")]
        inputs.events = [
            event("c1", kind: .cli, name: "git", session: "s1", cpu: 300, peak: 200_000_000),
            event("c2", kind: .cli, name: "npm", session: "s1", outcome: .error, cpu: 900, peak: 900_000_000, at: 1_000),
            event("c3", kind: .skill, name: "release-check", session: "s1", at: 2_000),
            event("c4", kind: .mcp, name: "github", session: "s2", outcome: .cancelled, at: 3_000),
            event("c5", kind: .mcp, name: "github", session: "s2", at: 4_000),
            event("c6", kind: .cli, name: "ls", session: "elsewhere", at: 5_000),
        ]
        inputs.meshEvents = snapshot().events
        inputs.loadHistory = ["Mac.lan": [
            LoadHistoryPoint(at: now - 120_000, agents: [.init(agent: "claude", cpuPercent: 40, memoryBytes: 1_000_000_000, processes: 3)]),
            LoadHistoryPoint(at: now - 60_000, agents: [.init(agent: "claude", cpuPercent: 80, memoryBytes: 2_000_000_000, processes: 4),
                                                        .init(agent: "codex", cpuPercent: 10, memoryBytes: 500_000_000, processes: 1)]),
        ]]
        inputs.latestLoad = ["Mac.lan": MachineLoad(
            machine: "Mac.lan", monitorCpuPercent: 1, monitorMemoryBytes: 2,
            agents: [AgentLoadSample(agent: "claude", disk: AgentDiskUsage(
                measuredAt: now, totalBytes: 3_000_000_000, entries: [DiskUsageEntry(path: "~/.claude", bytes: 3_000_000_000)]
            ))], generatedAt: now
        )]
        inputs.computerName = { $0 == "Mac.lan" ? "Studio" : $0 }
        return inputs
    }

    func testAProjectReportAddsUpEveryChatAndNamesWhatWentWrong() {
        let report = ReportBuilder.build(.project(snapshot()), inputs: inputs())
        XCTAssertEqual(report.title, "nodvox")
        XCTAssertTrue(report.subtitle.contains("Studio"), report.subtitle)
        let figure = { (label: String) in report.figures.first { $0.label == L(label) } }
        XCTAssertEqual(figure("Tokens")?.value, "15.0k", "each chat once, however many times it is listed")
        XCTAssertEqual(figure("Tool calls")?.value, "5", "the call from another Project is not counted")
        XCTAssertEqual(figure("Wrong turns")?.value, "3", "one failure, one cancel, one blocked Task")
        XCTAssertEqual(figure("CPU time")?.value, "1.2s")
        XCTAssertEqual(figure("Peak memory")?.value, "858 MB")
        XCTAssertEqual(figure("Disk")?.value, "2.8 GB")
        XCTAssertNotNil(figure("Wall time"))
        XCTAssertEqual(report.tables.map(\.title), [L("Tools"), L("Skills used"), L("MCP servers used"), L("Wrong turns"), L("Executions"), L("Machine load")])
        let tools = report.tables[0]
        XCTAssertEqual(tools.rows.first?[1], "npm", "the failing tool reads first")
        XCTAssertEqual(report.tables[1].rows, [["release-check", "1", "0", ReportBuilder.stamp(now - 3_600_000 + 2_000)]])
        XCTAssertEqual(report.tables[2].rows.first?.prefix(3), ["github", "2", "0"])
        let wrong = report.tables[3]
        XCTAssertEqual(wrong.rows.count, 3)
        XCTAssertEqual(wrong.rows[0][1], L("Failed call"))
        XCTAssertEqual(wrong.rows[1][1], L("Cancelled call"))
        XCTAssertEqual(wrong.rows[2][1], L("Task blocked"))
        XCTAssertEqual(wrong.rows[2][3], "Handoff is not ready.")
        let executions = report.tables[4]
        XCTAssertEqual(executions.rows.count, 2)
        XCTAssertEqual(executions.rows[0][1], "Studio")
        XCTAssertEqual(executions.rows[0][5], L("open"))
        XCTAssertEqual(executions.rows[1][5], ReportBuilder.stamp(now - 1_800_000))
        let load = report.tables[5]
        XCTAssertEqual(load.rows.count, 2)
        XCTAssertEqual(load.rows[0], ["Studio", "Claude Code", "60%", "80%", "1.9 GB", "2"])
        XCTAssertEqual(load.rows[1], ["Studio", "Codex", "10%", "10%", "477 MB", "1"])
        XCTAssertEqual(report.periodStart, Date(timeIntervalSince1970: (now - 7_200_000) / 1_000))
        XCTAssertEqual(report.periodEnd, Date(timeIntervalSince1970: (now - 30_000) / 1_000), "the blocked Task is the last thing that happened")
        XCTAssertTrue(report.fileStem.hasPrefix("nodvox-report-"), report.fileStem)
        XCTAssertFalse(report.periodLine.isEmpty)
    }

    func testATaskReportKeepsToTheTaskAndAChatReportToTheChat() {
        let task = ReportBuilder.build(.task(snapshot(), snapshot().tasks[1]), inputs: inputs())
        XCTAssertEqual(task.title, "Reports")
        XCTAssertEqual(task.figures.first { $0.label == L("Tokens") }?.value, "3.0k")
        XCTAssertEqual(task.figures.first { $0.label == L("Tool calls") }?.value, "2")
        XCTAssertEqual(task.figures.first { $0.label == L("Wrong turns") }?.value, "1", "the blocked Task belongs to t1")
        XCTAssertNil(task.tables.first { $0.title == L("Skills used") })
        XCTAssertEqual(task.tables.first { $0.title == L("Executions") }?.rows.count, 1)

        let chat = ReportBuilder.build(.chat(session("s1", agent: "claude", tokens: 500, taskId: "t1")), inputs: inputs())
        XCTAssertEqual(chat.title, "Chat s1")
        XCTAssertTrue(chat.subtitle.contains(L("Chat report")))
        XCTAssertEqual(chat.figures.first { $0.label == L("Tokens") }?.value, "12.0k", "the catalog's own record of the chat")
        XCTAssertEqual(chat.figures.first { $0.label == L("Tool calls") }?.value, "3")
        let executions = chat.tables.first { $0.title == L("Executions") }
        XCTAssertEqual(executions?.rows.count, 1, "a chat without executions lists itself")
        XCTAssertEqual(executions?.rows.first?[0], "Claude Code")

        let empty = ReportBuilder.build(.chat(session("nobody", agent: "cursor", tokens: 0, taskId: "none")), inputs: ReportInputs())
        XCTAssertEqual(empty.figures.first { $0.label == L("Tokens") }?.value, "—")
        XCTAssertEqual(empty.tables.first?.rows.first?.first, L("No observed tool calls"))
        XCTAssertEqual(empty.periodLine, L("No activity recorded yet"))
        XCTAssertNil(empty.figures.first { $0.label == L("Disk") })
        XCTAssertEqual(ReportBuilder.stamp(0), "")
        XCTAssertEqual(ReportBuilder.meshLabel("HANDOFF_REJECTED"), L("Handoff failed"))
        XCTAssertEqual(ReportBuilder.meshLabel("CONFLICT"), L("Conflict detected"))
        XCTAssertEqual(ReportBuilder.meshLabel("OTHER"), "OTHER")
        XCTAssertEqual(ReportBuilder.kindLabel(.mcp), "MCP")
        XCTAssertEqual(ReportBuilder.kindLabel(.skill), L("Skill"))
        XCTAssertEqual(ProjectReport(title: "  ", subtitle: "", generatedAt: Date(timeIntervalSince1970: 0), periodStart: nil,
                                     periodEnd: nil, figures: [], tables: [], notes: []).fileStem.hasPrefix("granttap-report-"), true)
    }

    func testCSVKeepsCommasAndQuotesInsideTheirCells() {
        let report = ReportBuilder.build(.project(snapshot()), inputs: inputs())
        let csv = ReportCSV.render(report)
        XCTAssertTrue(csv.hasPrefix("nodvox,"), String(csv.prefix(40)))
        let quoted = ProjectReport(title: "q", subtitle: "s", generatedAt: Date(), periodStart: nil, periodEnd: nil, figures: [],
                                   tables: [.init(title: "T", columns: ["a"], rows: [["npm --version, quoted \"yes\""]])], notes: [])
        XCTAssertTrue(ReportCSV.render(quoted).contains("\"npm --version, quoted \"\"yes\"\"\""), "a cell with a comma and quotes stays one cell")
        XCTAssertTrue(csv.contains("\r\n\(L("Tools"))\r\n"))
        XCTAssertTrue(csv.contains(L("From the load samples this phone kept while it was connected.")))
        XCTAssertEqual(ReportCSV.row(["a", "b,c", "d\"e", "f\ng"]), "a,\"b,c\",\"d\"\"e\",\"f\ng\"")
        let data = ReportCSV.data(report)
        XCTAssertEqual(Array(data.prefix(3)), [0xEF, 0xBB, 0xBF])
    }

    func testPDFRendersEveryTableAcrossPages() throws {
        var big = inputs()
        big.events = (0..<160).map { index in
            event("m\(index)", kind: .cli, name: "tool\(index)", session: "s1", outcome: index % 7 == 0 ? .error : .success, at: Double(index))
        }
        let report = ReportBuilder.build(.project(snapshot()), inputs: big)
        let data = ReportPDF.render(report)
        XCTAssertTrue(data.starts(with: Array("%PDF".utf8)))
        let document = try XCTUnwrap(PDFDocument(data: data))
        XCTAssertGreaterThan(document.pageCount, 1, "a long table continues on the next page with its header")
        XCTAssertEqual(document.documentAttributes?[PDFDocumentAttribute.titleAttribute] as? String, "nodvox")
        let text = (0..<document.pageCount).compactMap { document.page(at: $0)?.string }.joined()
        XCTAssertTrue(text.contains("tool159"), "the last row made it onto a page")
        XCTAssertTrue(text.contains(L("Wrong turns")))

        let small = ReportPDF.render(ReportBuilder.build(.chat(session("s9", agent: "cursor", tokens: 1, taskId: "t")), inputs: ReportInputs()))
        XCTAssertEqual(PDFDocument(data: small)?.pageCount, 1)
    }

    func testFilesAreWrittenWhereTheShareSheetFindsThem() throws {
        let report = ReportBuilder.build(.project(snapshot()), inputs: inputs())
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("granttap-report-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let pdf = try ReportFiles.write(report, format: .pdf, directory: directory)
        XCTAssertEqual(pdf.pathExtension, "pdf")
        XCTAssertGreaterThan(try Data(contentsOf: pdf).count, 1_000)
        let csv = try ReportFiles.write(report, format: .csv, directory: directory)
        XCTAssertEqual(csv.lastPathComponent, "\(report.fileStem).csv")
        XCTAssertThrowsError(try ReportFiles.write(report, format: .csv, directory: URL(fileURLWithPath: "/nonexistent/granttap")))

        let sheet = ReportExportSheet(report: report, initialFormat: .csv)
        XCTAssertNotNil(sheet.share())
        RenderProbe.render(sheet)
        RenderProbe.render(ReportExportSheet(report: report))
        XCTAssertEqual(URL(string: "https://example.test/a")?.id, "https://example.test/a")
    }

    func testTheModelAssemblesTheReportFromWhatItHolds() {
        let model = AppModel()
        model.meshSnapshots = ["p": snapshot()]
        model.sessions = [session("s1", agent: "claude", tokens: 100, taskId: "t1")]
        let room = "room-\(UUID().uuidString)"
        var connection = LinkedComputer(id: room, pairing: PairingFixture.pairing(room: room), label: "Studio", addedAt: 1, lastCatalogAt: 1, lastMachineName: "Mac.lan")
        model.connectionRegistry = .init(connections: [connection], preferredId: room)
        model.machineLoadHistoryByRoom[room] = [LoadHistoryPoint(at: now, agents: [.init(agent: "claude", cpuPercent: 5, memoryBytes: 1, processes: 1)])]
        model.machineLoadByRoom[room] = MachineLoad(machine: "Mac.lan", monitorCpuPercent: 0, monitorMemoryBytes: 0, agents: [], generatedAt: now)
        let inputs = model.reportInputs(now: Date(timeIntervalSince1970: now / 1_000))
        XCTAssertEqual(inputs.loadHistory["Mac.lan"]?.count, 1)
        XCTAssertNotNil(inputs.latestLoad["Mac.lan"])
        XCTAssertEqual(inputs.computerName("Mac.lan"), "Studio")
        XCTAssertEqual(inputs.computerName("Elsewhere"), "Elsewhere")
        let report = model.report(for: .project(snapshot()))
        XCTAssertEqual(report.title, "nodvox")
        XCTAssertEqual(report.tables.first { $0.title == L("Machine load") }?.rows.first?[0], "Studio")
        connection.lastMachineName = "  "
        XCTAssertEqual(ReportBuilder.computerKey(connection), room, "an unnamed computer is keyed by its pairing")
    }
}
