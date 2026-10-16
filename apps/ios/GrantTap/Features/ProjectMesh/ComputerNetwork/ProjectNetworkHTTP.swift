import Foundation

enum ProjectNetworkHTTP {
    static func publish(_ writer: ProjectNetworkWriter, pairing: Pairing) async throws {
        guard !pairing.isHub, let credential = pairing.pushAuth, !credential.isEmpty,
              var address = URLComponents(string: pairing.relayUrl) else { throw ProjectNetworkError.invalidScope }
        switch address.scheme {
        case "wss": address.scheme = "https"
        case "ws": address.scheme = "http"
        case "https", "http": break
        default: throw ProjectNetworkError.invalidScope
        }
        address.path = "/task-job-writers/\(writer.id)"
        address.queryItems = [URLQueryItem(name: "room", value: pairing.room)]
        guard let url = address.url else { throw ProjectNetworkError.invalidScope }
        var request = URLRequest(url: url, timeoutInterval: 20)
        request.httpMethod = "PUT"
        request.httpBody = try JSONEncoder().encode(writer.grant)
        request.setValue("Bearer \(credential)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let (data, response) = try await DeviceEndpointDirectory.boundedFetch(request)
        struct Response: Decodable {
            struct Writer: Decodable {
                let id: String
                let sourceKeyId: String
                let recipientKeyId: String
                let scopeHash: String
                let expiresAt: Double
            }
            let writer: Writer
        }
        guard let http = response as? HTTPURLResponse, [200, 201].contains(http.statusCode),
              let accepted = try? JSONDecoder().decode(Response.self, from: data),
              accepted.writer.id == writer.id, accepted.writer.sourceKeyId == writer.grant.sourceKeyId,
              accepted.writer.recipientKeyId == writer.grant.recipientKeyId,
              accepted.writer.scopeHash == writer.grant.scopeHash,
              accepted.writer.expiresAt == writer.grant.expiresAt else { throw ProjectNetworkError.relayUnavailable }
    }
}
