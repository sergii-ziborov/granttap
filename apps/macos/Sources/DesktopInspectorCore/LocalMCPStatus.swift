import Foundation

public struct LocalMCPStatus: Sendable {
    public enum RelayStatus: String, Decodable, Sendable {
        case online, offline, unknown
    }

    public enum Error: Swift.Error, Equatable {
        case unrecognizedService, unavailable, invalidPort
    }

    public struct Provider: Decodable, Sendable, Identifiable {
        public let id: String
        public let status: String
        public let detail: String
    }

    public struct Phone: Decodable, Sendable, Identifiable {
        public let name: String
        public let status: String
        public let lastSeenAt: Double?
        public var id: String { name }
    }

    public let computer: String
    public let version: String
    public let paired: Bool
    public let phoneReachability: LocalMCPHealth.Reachability
    public let phones: [Phone]
    public let relayHost: String
    public let relayStatus: RelayStatus
    public let providers: [Provider]
    public let desktopEngineSocket: String?
    public let supportsDesktopStatus: Bool

    private struct Wire: Decodable {
        let schema: String
        let ok: Bool
        let service: String
        let computer: String
        let version: String
        let paired: Bool
        let phoneReachability: LocalMCPHealth.Reachability
        let phones: [Phone]
        let relayHost: String
        let relayStatus: RelayStatus
        let providers: [Provider]
        let desktopEngineSocket: String?
    }

    public static func decode(_ body: Data) throws -> LocalMCPStatus {
        guard let wire = try? JSONDecoder().decode(Wire.self, from: body) else {
            throw Error.unrecognizedService
        }
        guard wire.schema == "granttap.desktop-status.v1", wire.ok,
              wire.service == "granttap-mcp", wire.computer.utf8.count <= 160,
              wire.version.utf8.count <= 64, wire.relayHost.utf8.count <= 255,
              wire.phones.count <= 16, wire.providers.count <= 16,
              wire.desktopEngineSocket.map({
                  $0.hasPrefix("/") && $0.utf8.count < 104
                      && !$0.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains)
              }) ?? true,
              wire.providers.allSatisfy({
                  $0.id.utf8.count <= 80 && $0.status.utf8.count <= 80
                      && $0.detail.utf8.count <= 512
              }) else { throw Error.unrecognizedService }
        return LocalMCPStatus(computer: wire.computer, version: wire.version,
                              paired: wire.paired, phoneReachability: wire.phoneReachability,
                              phones: wire.phones, relayHost: wire.relayHost,
                              relayStatus: wire.relayStatus, providers: wire.providers,
                              desktopEngineSocket: wire.desktopEngineSocket,
                              supportsDesktopStatus: true)
    }

    public static func fetch(
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) async throws -> LocalMCPStatus {
        let rawPort = environment["GRANTTAP_MCP_HTTP_PORT"] ?? "17342"
        guard let port = Int(rawPort), (1...65_535).contains(port),
              let url = URL(string: "http://127.0.0.1:\(port)/desktop/status") else {
            throw Error.invalidPort
        }
        var request = URLRequest(url: url)
        request.timeoutInterval = 8
        request.cachePolicy = .reloadIgnoringLocalCacheData
        let (body, response) = try await URLSession.shared.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode
        if status == 404 {
            let health = try await LocalMCPHealth.fetch(environment: environment)
            return LocalMCPStatus(computer: "This Mac", version: health.version ?? "Not reported",
                                  paired: health.paired, phoneReachability: health.phoneReachability,
                                  phones: [], relayHost: "", relayStatus: .unknown,
                                  providers: [], desktopEngineSocket: nil,
                                  supportsDesktopStatus: false)
        }
        guard status == 200 else { throw Error.unavailable }
        return try decode(body)
    }
}
