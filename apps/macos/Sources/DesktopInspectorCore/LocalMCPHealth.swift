import Foundation

public struct LocalMCPHealth: Sendable {
    public enum Reachability: String, Decodable, Sendable {
        case live, offline, unknown
    }

    public enum Error: Swift.Error, Equatable {
        case unrecognizedService
        case invalidPort
        case unavailable
    }

    public let paired: Bool
    public let phoneReachability: Reachability
    public let version: String?

    private struct Wire: Decodable {
        let schema: String
        let ok: Bool
        let service: String
        let version: String?
        let paired: Bool
        let phoneReachability: Reachability
    }

    public static func decode(_ body: Data) throws -> LocalMCPHealth {
        let wire = try JSONDecoder().decode(Wire.self, from: body)
        guard wire.schema == "granttap.http-health.v1", wire.ok,
              wire.service == "granttap-mcp" else {
            throw Error.unrecognizedService
        }
        return LocalMCPHealth(paired: wire.paired,
                              phoneReachability: wire.phoneReachability,
                              version: wire.version.flatMap {
                                  $0.isEmpty || $0.utf8.count > 64 ? nil : $0
                              })
    }

    public static func fetch(
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) async throws -> LocalMCPHealth {
        let rawPort = environment["GRANTTAP_MCP_HTTP_PORT"] ?? "17342"
        guard let port = Int(rawPort), (1...65_535).contains(port),
              let url = URL(string: "http://127.0.0.1:\(port)/healthz") else {
            throw Error.invalidPort
        }
        var request = URLRequest(url: url)
        request.timeoutInterval = 2
        request.cachePolicy = .reloadIgnoringLocalCacheData
        let (body, response) = try await URLSession.shared.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else {
            throw Error.unavailable
        }
        return try decode(body)
    }
}
