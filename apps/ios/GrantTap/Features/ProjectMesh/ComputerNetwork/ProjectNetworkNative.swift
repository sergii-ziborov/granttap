import Foundation

enum ProjectNetworkNative {
    static func descriptor(projectId: String) async throws -> ProjectNetworkEndpoint {
        struct Response: Decodable { let endpoint: ProjectNetworkEndpoint }
        return try JSONDecoder().decode(Response.self, from: await invoke(["action": "descriptor", "project_id": projectId])).endpoint
    }

    static func publish(_ writer: ProjectNetworkWriter, projectId: String) async throws {
        struct Response: Decodable { let accepted: Bool }
        let data = try JSONEncoder().encode(writer.grant)
        let response = try JSONDecoder().decode(Response.self, from: await invoke([
            "action": "grant", "project_id": projectId, "writer_id": writer.id, "grant": String(decoding: data, as: UTF8.self)]))
        guard response.accepted else { throw ProjectNetworkError.notConfirmed }
    }

    static func configure(_ command: ProjectTransportCommand) async throws -> ProjectTransportAck {
        struct Response: Decodable { let ack: ProjectTransportAck }
        let data = try JSONEncoder().encode(command)
        return try JSONDecoder().decode(Response.self, from: await invoke(["action": "configure",
            "project_id": command.projectId, "command": String(decoding: data, as: UTF8.self)])).ack
    }

    private static func invoke(_ input: [String: String]) async throws -> Data {
        #if targetEnvironment(macCatalyst)
        return try await MacNativeTransport.invoke(operation: "desktop.project_transport", input: input)
        #else
        throw ProjectNetworkError.invalidScope
        #endif
    }
}
