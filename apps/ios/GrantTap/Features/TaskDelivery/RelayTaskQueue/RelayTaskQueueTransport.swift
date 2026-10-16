import Foundation

/// HTTP acceptance is independent of the phone's WebSocket and the computer's online state.
struct RelayTaskQueueTransport {
    let pairing: Pairing
    var address: String? = nil
    var session: URLSession = .shared

    func upload(_ reservation: RelayTaskQueueReservation) async throws -> RelayTaskJobReceipt {
        let body = try await Task.detached(priority: .utility) {
            try RelayTaskQueueCipherStore.restore(reservation).uploadBody()
        }.value
        return try await request(reservation.jobId, method: "PUT", body: body)
    }

    func receipt(_ id: String) async throws -> RelayTaskJobReceipt {
        try await request(id, method: "GET")
    }

    func cancel(_ id: String) async throws -> RelayTaskJobReceipt {
        try await request(id, method: "DELETE")
    }

    private func request(_ id: String, method: String, body: Data? = nil) async throws -> RelayTaskJobReceipt {
        guard id.range(of: "^[A-Za-z0-9][A-Za-z0-9_-]{7,119}$", options: .regularExpression) != nil,
              var url = URLComponents(string: address ?? pairing.relayUrl),
              let credential = pairing.pushAuth, !credential.isEmpty else { throw RelayTaskQueueError.unavailable }
        switch url.scheme {
        case "wss": url.scheme = "https"
        case "ws": url.scheme = "http"
        case "https", "http": break
        default: throw RelayTaskQueueError.unavailable
        }
        url.path = "/task-jobs/\(id)"
        url.queryItems = [URLQueryItem(name: "room", value: pairing.room), URLQueryItem(name: "metadata", value: "1")]
        guard let address = url.url else { throw RelayTaskQueueError.unavailable }
        var request = URLRequest(url: address, timeoutInterval: 20)
        request.httpMethod = method
        request.httpBody = body
        request.setValue("Bearer \(credential)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if body != nil { request.setValue("application/json", forHTTPHeaderField: "Content-Type") }
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw RelayTaskQueueError.unavailable }
        switch http.statusCode {
        case 200, 201: break
        case 404, 405: throw RelayTaskQueueError.unsupported
        case 409: throw RelayTaskQueueError.conflict
        case 429: throw RelayTaskQueueError.full
        default: throw RelayTaskQueueError.unavailable
        }
        struct Response: Decodable { let job: RelayTaskJobReceipt }
        guard data.count < 20_000,
              let value = try? JSONDecoder().decode(Response.self, from: data), value.job.id == id else {
            throw RelayTaskQueueError.notConfirmed
        }
        return value.job
    }
}
