#if targetEnvironment(macCatalyst)
import Darwin
import Foundation

struct MacLocalMCPBridge {
    let socketPath: String
    private let maxFrame = 512 * 1_024

    func read(operation: String, input: [String: String]?, catalogAfter: String? = nil) throws -> Data {
        guard socketPath.hasPrefix("/"), socketPath.utf8.count < 104,
              socketPath.rangeOfCharacter(from: .controlCharacters) == nil else {
            throw MacLocalMCPError.untrusted
        }
        var info = stat()
        guard lstat(socketPath, &info) == 0, info.st_uid == getuid(),
              info.st_mode & mode_t(S_IFMT) == mode_t(S_IFSOCK),
              info.st_mode & 0o777 == 0o600 else { throw MacLocalMCPError.untrusted }
        let fd = Darwin.socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { throw MacLocalMCPError.unavailable }
        defer { _ = Darwin.close(fd) }
        let needsEngine = operation == "desktop.mesh_snapshot" && input?["enrich"] == "true"
        var timeout = timeval(tv_sec: operation == "desktop.capability_usage"
                              || operation == "desktop.mesh_snapshots" ? 75
                              : operation == "desktop.task_send"
                              || operation == "desktop.task_create"
                                || operation == "desktop.own_relay" ? 250
                              : operation == "desktop.provider_storage" ? 120
                              : operation == "desktop.policy_set" ? 60
                              : operation == "desktop.policy_status"
                                || operation == "desktop.controller_enrollment"
                                || operation == "desktop.codex_hook_trust" ? 30
                              : operation == "desktop.mesh_create" ? 15
                              : operation == "desktop.task_activity"
                                || operation == "desktop.task_image"
                                || operation == "desktop.live_catalog" ? 45
                              : needsEngine ? 45
                              : operation == "desktop.invocation_history" ? 12 : 5,
                              tv_usec: 0)
        _ = setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &timeout, socklen_t(MemoryLayout.size(ofValue: timeout)))
        _ = setsockopt(fd, SOL_SOCKET, SO_SNDTIMEO, &timeout, socklen_t(MemoryLayout.size(ofValue: timeout)))
        var address = sockaddr_un()
        address.sun_family = sa_family_t(AF_UNIX)
        let bytes = socketPath.utf8CString.map { UInt8(bitPattern: $0) }
        guard bytes.count <= MemoryLayout.size(ofValue: address.sun_path) else {
            throw MacLocalMCPError.untrusted
        }
        withUnsafeMutableBytes(of: &address.sun_path) { $0.copyBytes(from: bytes) }
        let connected = withUnsafePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                Darwin.connect(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        guard connected == 0 else { throw MacLocalMCPError.unavailable }
        let requestId = UUID().uuidString
        var request: [String: Any] = [
            "protocol_version": 1, "request_id": requestId, "operation": operation,
        ]
        if operation == "project.list" {
            var catalogInput: [String: Any] = ["limit": 50]
            if let catalogAfter { catalogInput["after_project_id"] = catalogAfter }
            request["input"] = catalogInput
        } else if let input { request["input"] = input }
        let body = try JSONSerialization.data(withJSONObject: request)
        guard body.count <= maxFrame else { throw MacLocalMCPError.incompatible }
        var length = UInt32(body.count).bigEndian
        var frame = withUnsafeBytes(of: &length) { Data($0) }
        frame.append(body)
        try writeAll(frame, fd: fd)
        let header = try readExact(4, fd: fd)
        let count = header.reduce(UInt32(0)) { ($0 << 8) | UInt32($1) }
        guard count > 0, count <= maxFrame else { throw MacLocalMCPError.incompatible }
        let response = try readExact(Int(count), fd: fd)
        guard let root = try JSONSerialization.jsonObject(with: response) as? [String: Any],
              root["protocol_version"] as? Int == 1,
              root["request_id"] as? String == requestId,
              root["status"] as? String == "ok",
              let result = root["result"] as? [String: Any],
              (operation == "desktop.mesh_snapshot"
                  ? result["type"] as? String == "mesh.snapshot"
                  : result["operation"] as? String == (operation == "project.list" ? "project.listed" : operation)) else {
            throw MacLocalMCPError.incompatible
        }
        return try JSONSerialization.data(withJSONObject: result)
    }

    private func writeAll(_ data: Data, fd: Int32) throws {
        var offset = 0
        while offset < data.count {
            let count = data.withUnsafeBytes { pointer in
                Darwin.write(fd, pointer.baseAddress!.advanced(by: offset), data.count - offset)
            }
            guard count > 0 else { throw MacLocalMCPError.unavailable }
            offset += count
        }
    }

    private func readExact(_ count: Int, fd: Int32) throws -> Data {
        var result = Data(count: count)
        var offset = 0
        while offset < count {
            let received = result.withUnsafeMutableBytes { pointer in
                Darwin.read(fd, pointer.baseAddress!.advanced(by: offset), count - offset)
            }
            guard received > 0 else { throw MacLocalMCPError.unavailable }
            offset += received
        }
        return result
    }
}
#endif
