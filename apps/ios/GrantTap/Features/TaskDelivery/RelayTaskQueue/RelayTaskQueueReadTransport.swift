import Foundation

extension RelayTaskQueueTransport {
    func activeJobs() async throws -> [RelayTaskJobReceipt] {
        struct Reply: Decodable { let jobs: [RelayTaskJobReceipt] }
        let data = try await readQueue(path: "/task-jobs", maximumBytes: 200_000)
        let rows = try JSONDecoder().decode(Reply.self, from: data).jobs
        guard rows.count <= 100 else { throw RelayTaskQueueError.notConfirmed }
        return rows
    }

    func storedJob(_ id: String) async throws -> RelayTaskQueueRecovery.StoredJob {
        guard id.range(of: "^[A-Za-z0-9][A-Za-z0-9_-]{7,119}$", options: .regularExpression) != nil else {
            throw RelayTaskQueueError.invalidMessage
        }
        struct Reply: Decodable { let job: RelayTaskQueueRecovery.StoredJob }
        return try JSONDecoder().decode(Reply.self,
            from: await readQueue(path: "/task-jobs/\(id)", maximumBytes: 22_010_000)).job
    }

    private func readQueue(path: String, maximumBytes: Int) async throws -> Data {
        guard var url = URLComponents(string: address ?? pairing.relayUrl),
              let credential = pairing.pushAuth, !credential.isEmpty else { throw RelayTaskQueueError.unavailable }
        url.scheme = url.scheme == "wss" ? "https" : url.scheme == "ws" ? "http" : url.scheme
        guard ["http", "https"].contains(url.scheme ?? "") else { throw RelayTaskQueueError.unavailable }
        url.path = path
        url.queryItems = [URLQueryItem(name: "room", value: pairing.room)]
        guard let address = url.url else { throw RelayTaskQueueError.unavailable }
        var request = URLRequest(url: address, timeoutInterval: 15)
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.setValue("Bearer \(credential)", forHTTPHeaderField: "Authorization")
        let (bytes, response) = try await session.bytes(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw RelayTaskQueueError.unavailable }
        var data = Data()
        for try await byte in bytes {
            guard data.count < maximumBytes else { throw RelayTaskQueueError.tooLarge }
            data.append(byte)
        }
        return data
    }
}
