import SwiftUI
import XCTest
@testable import GrantTap

@MainActor
final class ThreadEventsTests: XCTestCase {
    private let now = 1_800_000_000_000.0

    private func entry(_ id: String, thread: String? = nil, kind: String = "message", at offset: Double = 0,
                       tool: String? = nil, added: Int? = nil, removed: Int? = nil) -> ActivityEntry {
        ActivityEntry(id: id, kind: kind, text: kind == "tool" ? "\(tool ?? "Write"): /repo/a.swift" : "Text \(id)",
                      createdAt: now + offset, toolName: tool, childThreadId: thread,
                      childThreadTitle: thread.map { "Thread \($0)" }, childThreadDepth: thread == nil ? nil : 1,
                      linesAdded: added, linesRemoved: removed)
    }

    func testAFetchedConversationMergesIntoTheChatItBelongsTo() throws {
        let model = AppModel()
        // Activities persist across tests, so this chat is one nobody else has.
        let s = "thread-merge-\(UUID().uuidString)"
        model.applyActivity(SessionActivity(sessionId: s, agent: "claude", state: "idle",
                                            entries: [entry("root-1"), entry("root-2", at: 1_000)], generatedAt: now))
        XCTAssertEqual(model.activities[s]?.entries.count, 2)
        let fetched = SessionActivity(sessionId: s, agent: "claude", state: "idle", threadId: "t1",
                                      entries: [entry("child-1", thread: "t1", at: 500), entry("child-2", thread: "t1", at: 600)],
                                      generatedAt: now + 1)
        model.applyActivity(fetched)
        let merged = try XCTUnwrap(model.activities[s])
        XCTAssertEqual(merged.entries.map(\.id), ["root-1", "child-1", "child-2", "root-2"], "the conversation joins the chat in time order")
        XCTAssertEqual(merged.entries.filter { $0.childThreadId == "t1" }.count, 2)

        let decoded = try JSONDecoder().decode(SessionActivity.self, from: Data("""
        {"type":"session.activity","sessionId":"s","agent":"claude","state":"idle","threadId":"t1","entries":[],"generatedAt":1}
        """.utf8))
        XCTAssertEqual(decoded.threadId, "t1")
        let bare = try JSONDecoder().decode(SessionActivity.self, from: Data("""
        {"type":"session.activity","sessionId":"s","agent":"claude","state":"idle","entries":[],"generatedAt":1}
        """.utf8))
        XCTAssertNil(bare.threadId)

        let request = SessionEventsRequest(type: "session.events", sessionId: "s", threadId: "t1", createdAt: 1)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: RelayClient.encodeOmittingNulls(request)) as? [String: Any])
        XCTAssertEqual(object["threadId"] as? String, "t1")
        let plain = SessionEventsRequest(type: "session.events", sessionId: "s", createdAt: 1)
        let plainObject = try XCTUnwrap(JSONSerialization.jsonObject(with: RelayClient.encodeOmittingNulls(plain)) as? [String: Any])
        XCTAssertNil(plainObject["threadId"], "absent, not null, on the wire")
    }

    func testAConversationIsAskedForOnceAtATime() {
        let model = AppModel()
        let room = "thread-\(UUID().uuidString)"
        model.connectionRegistry = ConnectionRegistryLogic.upsert(.empty, pairing: PairingFixture.pairing(room: room))
        model.relaysByRoom[room] = RelayClient(pairing: PairingFixture.pairing(room: room))
        model.rememberSessionSourceRoom(room, sessionId: "s")
        model.requestThreadEvents("s", threadId: "t1", now: now)
        model.requestThreadEvents("s", threadId: "t1", now: now + 5_000)
        XCTAssertEqual(model.threadEventRequestsAt.count, 1)
        XCTAssertEqual(model.threadEventRequestsAt["s\u{1f}t1"], now, "the second tap within the interval changes nothing")
        model.requestThreadEvents("s", threadId: "t1", now: now + 30_000)
        XCTAssertEqual(model.threadEventRequestsAt["s\u{1f}t1"], now + 30_000)
        model.requestThreadEvents("s", threadId: "t2", now: now)
        XCTAssertEqual(model.threadEventRequestsAt.count, 2)
    }

    func testTheCardSaysWhenItRanAndAsksForItsRowsWhenOpenedEmpty() {
        let thread = ChildThreadInfo(threadId: "t1", parentThreadId: "s", title: "Audit", depth: 1, state: "idle",
                                     startedAt: now - 3_600_000, lastActivityAt: now - 600_000, tokensSession: 10, tokensLastTurn: 1)
        let line = ThreadTimeline.line(thread, now: now)
        XCTAssertTrue(line.hasPrefix(String(format: L("started %@"), ReportBuilder.stamp(now - 3_600_000))), line)
        XCTAssertTrue(line.contains(L("last active")), line)
        var working = thread
        working.state = "working"
        XCTAssertTrue(ThreadTimeline.line(working, now: now).contains(L("active now")))
        let unknown = ChildThreadInfo(threadId: "t2", parentThreadId: "s", title: nil, depth: 1, state: "idle",
                                      startedAt: 0, lastActivityAt: 0, tokensSession: 0, tokensLastTurn: 0)
        XCTAssertEqual(ThreadTimeline.line(unknown), "")

        var asked = 0
        let row = ChildThreadDisplayRow(thread: thread, visualDepth: 1)
        let card = AgentThreadTranscript(row: row, entries: [], accent: .red, servers: [], expanded: true) { asked += 1 }
        RenderProbe.render(card.environmentObject(AppModel()))
        XCTAssertEqual(asked, 1, "opened on nothing, the card asks once")
        let filled = AgentThreadTranscript(row: row, entries: [entry("c", thread: "t1")], accent: .red, servers: [], expanded: true) { asked += 1 }
        RenderProbe.render(filled.environmentObject(AppModel()))
        XCTAssertEqual(asked, 1, "a card with rows has nothing to ask for")
        RenderProbe.render(AgentThreadTranscript(row: row, entries: [], accent: .red, servers: []).environmentObject(AppModel()))
    }

    func testAFileToolReadsLikeGit() throws {
        let write = entry("w", kind: "tool", tool: "Write", added: 12, removed: 3)
        XCTAssertEqual(write.diffStats?.added, 12)
        XCTAssertEqual(write.diffStats?.removed, 3)
        XCTAssertNil(entry("r", kind: "tool", tool: "Read").diffStats)
        XCTAssertNil(entry("z", kind: "tool", tool: "Write", added: 0, removed: 0).diffStats)
        let decoded = try JSONDecoder().decode(ActivityEntry.self, from: Data("""
        {"id":"e","kind":"tool","text":"Edit: /a","createdAt":1,"toolName":"Edit","linesAdded":2,"linesRemoved":1}
        """.utf8))
        XCTAssertEqual(decoded.linesAdded, 2)
        XCTAssertEqual(decoded.linesRemoved, 1)
        let negative = try JSONDecoder().decode(ActivityEntry.self, from: Data("""
        {"id":"e","kind":"tool","text":"Edit: /a","createdAt":1,"toolName":"Edit","linesAdded":-2}
        """.utf8))
        XCTAssertNil(negative.linesAdded)
        RenderProbe.render(DiffStatsBadge(added: 12, removed: 3))
        RenderProbe.render(DiffStatsBadge(added: 0, removed: 3))
        RenderProbe.render(ActivityRow(entry: write, accent: .red, compact: false).environmentObject(AppModel()))
    }
}

extension ThreadEventsTests {
    func testAnOpenedFileToolShowsItsChangeInColour() throws {
        let decoded = try JSONDecoder().decode(ActivityEntry.self, from: Data("""
        {"id":"e","kind":"tool","text":"Edit: /a","createdAt":1,"toolName":"Edit","linesAdded":2,"linesRemoved":1,"diffPreview":"-b\\n+B\\n+C\\n context\\n… 3 more lines"}
        """.utf8))
        XCTAssertEqual(decoded.diffPreview?.components(separatedBy: "\n").count, 5)
        XCTAssertEqual(DiffLineKind.of("+B"), .added)
        XCTAssertEqual(DiffLineKind.of("-b"), .removed)
        XCTAssertEqual(DiffLineKind.of(" context"), .context)
        XCTAssertEqual(DiffLineKind.of("… 3 more lines"), .note)
        XCTAssertEqual(DiffPreviewView.ground(.context), .clear)
        XCTAssertNotEqual(DiffPreviewView.ink(.added), DiffPreviewView.ink(.removed))
        RenderProbe.render(DiffPreviewView(text: decoded.diffPreview ?? ""))
        var opened = ActivityEntry(id: "w", kind: "tool", text: "Write: /repo/a.swift", createdAt: 1, toolName: "Write",
                                   linesAdded: 3, linesRemoved: 0, diffPreview: "+a\n+b\n+c")
        RenderProbe.render(ActivityRow(entry: opened, accent: .red, compact: false, initiallyExpanded: true).environmentObject(AppModel()))
        opened.diffPreview = nil
        RenderProbe.render(ActivityRow(entry: opened, accent: .red, compact: false, initiallyExpanded: true).environmentObject(AppModel()))
        let huge = String(repeating: "+x\n", count: 3_000)
        let bounded = try JSONDecoder().decode(ActivityEntry.self, from: JSONSerialization.data(withJSONObject: [
            "id": "e", "kind": "tool", "text": "Write: /a", "createdAt": 1, "toolName": "Write", "diffPreview": huge,
        ]))
        XCTAssertEqual(bounded.diffPreview?.count, 4_000, "the phone keeps what the wire allows and no more")
    }
}
