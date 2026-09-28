import Darwin
import Dispatch
import Foundation

public final class EngineClient: @unchecked Sendable {
    public let socketPath: String
    private let timeoutSeconds: Double
    private let capacity = DispatchSemaphore(value: 1)

    public init(socketPath: String, timeoutSeconds: Double = 2) {
        self.socketPath = socketPath
        self.timeoutSeconds = timeoutSeconds
    }

    public static var configuredSocketPath: String {
        ProcessInfo.processInfo.environment["GRANTTAP_ENGINE_SOCKET"] ?? ""
    }

    public func request(_ query: EngineQuery) throws -> Data {
        guard capacity.wait(timeout: .now()) == .success else { throw EngineClientError.busy }
        defer { capacity.signal() }
        let requestId = UUID().uuidString
        let frame = try EngineCodec.encode(query, requestId: requestId)
        let payload = try UnixSocketExchange(path: socketPath, timeoutSeconds: timeoutSeconds)
            .send(frame)
        return try EngineCodec.result(payload, for: query, requestId: requestId)
    }
}

struct UnixSocketExchange {
    let path: String
    let timeoutSeconds: Double

    func send(_ frame: Data) throws -> Data {
        try validateSocket()
        let fd = Darwin.socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { throw EngineClientError.unavailable }
        defer { _ = Darwin.close(fd) }
        guard fcntl(fd, F_SETFL, O_NONBLOCK) == 0 else { throw EngineClientError.unavailable }
        let deadline = DispatchTime.now().uptimeNanoseconds
            + UInt64(max(0.1, min(timeoutSeconds, 30)) * 1_000_000_000)
        try connect(fd, deadline: deadline)
        try write(frame, fd: fd, deadline: deadline)
        let header = try read(4, fd: fd, deadline: deadline)
        let length = header.reduce(UInt32(0)) { ($0 << 8) | UInt32($1) }
        guard length > 0, length <= EngineCodec.maxFrameBytes else {
            throw EngineClientError.invalidFrame
        }
        return try read(Int(length), fd: fd, deadline: deadline)
    }

    private func validateSocket() throws {
        guard path.hasPrefix("/"), path.utf8.count < 104 else {
            throw EngineClientError.socketUntrusted
        }
        var info = stat()
        guard lstat(path, &info) == 0 else {
            throw errno == ENOENT ? EngineClientError.unavailable : EngineClientError.socketUntrusted
        }
        guard info.st_uid == getuid(),
              info.st_mode & mode_t(S_IFMT) == mode_t(S_IFSOCK),
              info.st_mode & 0o777 == 0o600 else {
            throw EngineClientError.socketUntrusted
        }
    }

    private func connect(_ fd: Int32, deadline: UInt64) throws {
        var address = sockaddr_un()
        address.sun_family = sa_family_t(AF_UNIX)
        let bytes = path.utf8CString.map { UInt8(bitPattern: $0) }
        guard bytes.count <= MemoryLayout.size(ofValue: address.sun_path) else {
            throw EngineClientError.socketUntrusted
        }
        withUnsafeMutableBytes(of: &address.sun_path) { $0.copyBytes(from: bytes) }
        let status = withUnsafePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                Darwin.connect(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        if status == 0 { return }
        guard errno == EINPROGRESS else { throw EngineClientError.unavailable }
        try wait(fd, events: Int16(POLLOUT), deadline: deadline)
        var error: Int32 = 0
        var size = socklen_t(MemoryLayout<Int32>.size)
        guard getsockopt(fd, SOL_SOCKET, SO_ERROR, &error, &size) == 0, error == 0 else {
            throw EngineClientError.unavailable
        }
    }

    private func write(_ data: Data, fd: Int32, deadline: UInt64) throws {
        var offset = 0
        while offset < data.count {
            try wait(fd, events: Int16(POLLOUT), deadline: deadline)
            let count = data.withUnsafeBytes { pointer in
                Darwin.write(fd, pointer.baseAddress!.advanced(by: offset), data.count - offset)
            }
            if count > 0 { offset += count; continue }
            if count < 0 && (errno == EINTR || errno == EAGAIN) { continue }
            throw EngineClientError.unavailable
        }
    }

    private func read(_ count: Int, fd: Int32, deadline: UInt64) throws -> Data {
        var result = Data(count: count)
        var offset = 0
        while offset < count {
            try wait(fd, events: Int16(POLLIN), deadline: deadline)
            let received = result.withUnsafeMutableBytes { pointer in
                Darwin.read(fd, pointer.baseAddress!.advanced(by: offset), count - offset)
            }
            if received > 0 { offset += received; continue }
            if received < 0 && (errno == EINTR || errno == EAGAIN) { continue }
            throw EngineClientError.invalidFrame
        }
        return result
    }

    private func wait(_ fd: Int32, events: Int16, deadline: UInt64) throws {
        while true {
            let now = DispatchTime.now().uptimeNanoseconds
            guard now < deadline else { throw EngineClientError.deadlineExceeded }
            let milliseconds = Int32(min((deadline - now) / 1_000_000 + 1, UInt64(Int32.max)))
            var item = pollfd(fd: fd, events: events, revents: 0)
            let result = Darwin.poll(&item, 1, milliseconds)
            if result > 0 {
                guard item.revents & Int16(POLLNVAL | POLLERR) == 0 else {
                    throw EngineClientError.unavailable
                }
                if item.revents & events != 0 { return }
                if item.revents & Int16(POLLHUP) != 0 {
                    throw EngineClientError.unavailable
                }
            } else if result == 0 {
                throw EngineClientError.deadlineExceeded
            } else if errno != EINTR {
                throw EngineClientError.unavailable
            }
        }
    }
}
