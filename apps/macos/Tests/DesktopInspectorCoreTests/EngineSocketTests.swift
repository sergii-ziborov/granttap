import Darwin
import Dispatch
import Foundation
import Testing
@testable import DesktopInspectorCore

@Test func clientReadsFragmentedResponseFromOwnerOnlySocket() throws {
    let server = try TestEngineServer()
    defer { server.stop() }
    server.respondWithVersion(fragmentBytes: 3)
    let payload = try EngineClient(socketPath: server.path).request(.version)
    let version = try JSONDecoder().decode(EngineVersion.self, from: payload)
    #expect(version.engine_version == "test-engine")
    server.wait()
}

@Test func clientRejectsWorldReadableSocket() throws {
    let server = try TestEngineServer()
    defer { server.stop() }
    guard chmod(server.path, 0o644) == 0 else { throw EngineClientError.unavailable }
    #expect(throws: EngineClientError.socketUntrusted) {
        _ = try EngineClient(socketPath: server.path).request(.version)
    }
}

@Test func missingSocketIsReportedAsUnavailable() {
    let path = "/tmp/gti-missing-\(UUID().uuidString.prefix(8)).sock"
    #expect(throws: EngineClientError.unavailable) {
        _ = try EngineClient(socketPath: path).request(.version)
    }
}

private final class TestEngineServer: @unchecked Sendable {
    let path: String
    private let directory: URL
    private let listener: Int32
    private let group = DispatchGroup()

    init() throws {
        directory = URL(fileURLWithPath: "/tmp/gti-\(UUID().uuidString.prefix(8))")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        path = directory.appendingPathComponent("engine.sock").path
        listener = Darwin.socket(AF_UNIX, SOCK_STREAM, 0)
        guard listener >= 0 else { throw EngineClientError.unavailable }
        var address = sockaddr_un()
        address.sun_family = sa_family_t(AF_UNIX)
        let bytes = path.utf8CString.map { UInt8(bitPattern: $0) }
        guard bytes.count <= MemoryLayout.size(ofValue: address.sun_path) else {
            throw EngineClientError.invalidRequest
        }
        withUnsafeMutableBytes(of: &address.sun_path) { $0.copyBytes(from: bytes) }
        let bound = withUnsafePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                Darwin.bind(listener, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        guard bound == 0, chmod(path, 0o600) == 0, listen(listener, 1) == 0 else {
            throw EngineClientError.unavailable
        }
    }

    func respondWithVersion(fragmentBytes: Int) {
        group.enter()
        DispatchQueue.global(qos: .userInitiated).async {
            defer { self.group.leave() }
            let connection = Darwin.accept(self.listener, nil, nil)
            guard connection >= 0 else { return }
            defer { _ = Darwin.close(connection) }
            guard let header = self.read(4, from: connection) else { return }
            let count = header.reduce(0) { ($0 << 8) | Int($1) }
            guard let request = self.read(count, from: connection),
                  let object = try? JSONSerialization.jsonObject(with: request) as? [String: Any],
                  let requestId = object["request_id"] as? String else { return }
            let response: [String: Any] = [
                "protocol_version": 1, "request_id": requestId, "status": "ok",
                "result": ["operation": "engine.version", "protocol_version": 1,
                           "engine_version": "test-engine", "cortex_version": "test",
                           "cortex_revision": "test", "weavatrix_version": "test"],
            ]
            guard let payload = try? JSONSerialization.data(withJSONObject: response) else { return }
            var length = UInt32(payload.count).bigEndian
            let frame = withUnsafeBytes(of: &length) { Data($0) } + payload
            for part in stride(from: 0, to: frame.count, by: fragmentBytes) {
                let chunk = frame.subdata(in: part..<min(part + fragmentBytes, frame.count))
                chunk.withUnsafeBytes { pointer in
                    _ = Darwin.write(connection, pointer.baseAddress!, chunk.count)
                }
            }
        }
    }

    func wait() { group.wait() }

    func stop() {
        _ = Darwin.close(listener)
        try? FileManager.default.removeItem(at: directory)
    }

    private func read(_ count: Int, from fd: Int32) -> Data? {
        guard (1...EngineCodec.maxFrameBytes).contains(count) else { return nil }
        var data = Data(count: count)
        var offset = 0
        while offset < count {
            let received = data.withUnsafeMutableBytes { pointer in
                Darwin.read(fd, pointer.baseAddress!.advanced(by: offset), count - offset)
            }
            guard received > 0 else { return nil }
            offset += received
        }
        return data
    }
}
