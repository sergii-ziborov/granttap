import Darwin
import Foundation
@testable import DesktopInspectorCore

final class RealEngineFixture {
    let socketPath: String
    let workspacePath: String
    private let directory: URL
    private let process: Process

    init(binaryPath: String) throws {
        directory = URL(fileURLWithPath: "/tmp/gtd-fixture-\(UUID().uuidString.prefix(8))")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        socketPath = directory.appendingPathComponent("engine.sock").path
        workspacePath = directory.appendingPathComponent("workspace").path
        try FileManager.default.createDirectory(atPath: workspacePath,
                                                withIntermediateDirectories: true)
        process = Process()
        process.executableURL = URL(fileURLWithPath: binaryPath)
        process.environment = ["GRANTTAP_ENGINE_SOCKET": socketPath]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
            try waitForSocket()
            try seed()
        } catch {
            if process.isRunning { process.terminate(); process.waitUntilExit() }
            try? FileManager.default.removeItem(at: directory)
            throw error
        }
    }

    deinit {
        if process.isRunning { process.terminate(); process.waitUntilExit() }
        try? FileManager.default.removeItem(at: directory)
    }

    private func waitForSocket() throws {
        for _ in 0..<200 {
            if FileManager.default.fileExists(atPath: socketPath) { return }
            if !process.isRunning { throw EngineClientError.unavailable }
            Thread.sleep(forTimeInterval: 0.01)
        }
        throw EngineClientError.deadlineExceeded
    }

    private func seed() throws {
        let project = "desktop-integration-project"
        try send("project.upsert_binding", id: "binding", input: [
            "project": ["project_id": project, "name": "Desktop Integration", "created_at": 1],
            "binding": ["binding_id": "desktop-integration-binding", "project_id": project,
                        "endpoint_id": "desktop-integration-mac",
                        "repository_id": "desktop-integration-repo", "role": "primary",
                        "local_root": workspacePath,
                        "last_seen_at": 1],
        ])
        try applyPolicy(revision: 1)
        try send("policy.ack", id: "coverage", input: [
            "acknowledgement": ["project_id": project, "policy_revision": 1,
                                "endpoint_id": "desktop-integration-mac", "provider": "codex",
                                "capabilities": [["kind": "shell", "status": "enforced"]],
                                "observed_at": 3],
        ])
        let first = [("public-a", "task-a", "project", "user_decision"),
                     ("private-a", "task-a", "task", "agent_report"),
                     ("private-b", "task-b", "task", "agent_report")]
        for (index, row) in first.enumerated() {
            try record(project: project, id: row.0, task: row.1,
                       visibility: row.2, source: row.3, order: index + 1)
        }
        for index in 1...25 {
            try record(project: project, id: String(format: "public-%02d", index),
                       task: "task-a", visibility: "project",
                       source: "user_decision", order: index + 10)
        }
        for index in 1...35 {
            let task = index == 2 ? "task-b" : "task-a"
            try send("invocation.observe", id: "event-request-\(index)", input: [
                "event_id": "event-\(index)", "invocation_id": "call-\(index)",
                "project_id": project, "task_id": task,
                "execution_id": "execution-\(index)", "provider": "codex",
                "native_call_id": "native-\(index)", "tool_name": "Read",
                "phase": "reported_success", "source": "transcript", "occurred_at": index,
            ])
        }
    }

    func advancePolicy() throws { try applyPolicy(revision: 2) }

    private func applyPolicy(revision: Int) throws {
        let project = "desktop-integration-project"
        try send("policy.apply", id: "policy-\(revision)", input: [
            "expected_revision": revision - 1,
            "policy": ["project_id": project, "revision": revision,
                       "enforcement": "strict",
                       "rules": [["rule_id": "deny-shell", "project_id": project,
                                  "selector": ["kind": "shell"], "effect": "deny",
                                  "revision": revision, "created_by": "fixture"]]],
        ])
    }

    private func record(project: String, id: String, task: String,
                        visibility: String, source: String, order: Int) throws {
        try send("memory.record", id: "record-request-\(id)", input: [
            "project_id": project, "task_id": task, "record_id": id,
            "category": "decision", "content": "harmless integration fixture \(order)",
            "source": source, "source_ref": "fixture-\(id)",
            "visibility": visibility, "recorded_at": order,
        ])
    }

    private func send(_ operation: String, id: String, input: [String: Any]) throws {
        let payload = try JSONSerialization.data(withJSONObject: [
            "protocol_version": 1, "request_id": id, "operation": operation, "input": input,
        ])
        var length = UInt32(payload.count).bigEndian
        let frame = withUnsafeBytes(of: &length) { Data($0) } + payload
        let fd = Darwin.socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { throw EngineClientError.unavailable }
        defer { _ = Darwin.close(fd) }
        var address = sockaddr_un()
        address.sun_family = sa_family_t(AF_UNIX)
        let bytes = socketPath.utf8CString.map { UInt8(bitPattern: $0) }
        guard bytes.count <= MemoryLayout.size(ofValue: address.sun_path) else {
            throw EngineClientError.invalidRequest
        }
        withUnsafeMutableBytes(of: &address.sun_path) { $0.copyBytes(from: bytes) }
        let connected = withUnsafePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                Darwin.connect(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        guard connected == 0 else { throw EngineClientError.unavailable }
        try frame.withUnsafeBytes { pointer in
            try writeAll(fd, pointer.baseAddress!, frame.count)
        }
        let header = try readAll(fd, 4)
        let size = header.reduce(0) { ($0 << 8) | Int($1) }
        guard (1...EngineCodec.maxFrameBytes).contains(size) else {
            throw EngineClientError.invalidFrame
        }
        let response = try JSONSerialization.jsonObject(with: readAll(fd, size)) as? [String: Any]
        guard response?["status"] as? String == "ok" else {
            throw EngineClientError.remoteFailure
        }
    }

    private func writeAll(_ fd: Int32, _ pointer: UnsafeRawPointer, _ size: Int) throws {
        var offset = 0
        while offset < size {
            let count = Darwin.write(fd, pointer.advanced(by: offset), size - offset)
            guard count > 0 else { throw EngineClientError.unavailable }
            offset += count
        }
    }

    private func readAll(_ fd: Int32, _ size: Int) throws -> Data {
        var data = Data(count: size)
        var offset = 0
        while offset < size {
            let count = data.withUnsafeMutableBytes { pointer in
                Darwin.read(fd, pointer.baseAddress!.advanced(by: offset), size - offset)
            }
            guard count > 0 else { throw EngineClientError.invalidFrame }
            offset += count
        }
        return data
    }
}
