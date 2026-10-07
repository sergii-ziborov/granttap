#if targetEnvironment(macCatalyst)
import Foundation

private final class MacNativeNoRedirect: NSObject, URLSessionTaskDelegate {
    func urlSession(_ session: URLSession, task: URLSessionTask,
                    willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest,
                    completionHandler: @escaping (URLRequest?) -> Void) { completionHandler(nil) }
}

enum MacNativeTransport {
    static func fetch(_ input: URLRequest, limit: Int = 512 * 1_024,
                      timeout: TimeInterval = 260) async throws -> Data {
        var request = input
        request.timeoutInterval = timeout
        let session = URLSession(configuration: .ephemeral, delegate: MacNativeNoRedirect(), delegateQueue: nil)
        defer { session.invalidateAndCancel() }
        let (bytes, response) = try await session.bytes(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else {
            throw MacLocalMCPError.untrusted
        }
        var data = Data()
        for try await byte in bytes {
            guard data.count < limit else { throw MacLocalMCPError.incompatible }
            data.append(byte)
        }
        return data
    }

    static func invoke(operation: String, input: [String: Any]?) async throws -> Data {
        guard let token = await MacNativeAccess.shared.token else { throw MacLocalMCPError.untrusted }
        var request = URLRequest(url: await MacNativeAccess.baseURL.appendingPathComponent("desktop/invoke"))
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        var payload: [String: Any] = ["operation": operation]
        if let input { payload["input"] = input }
        request.httpBody = try JSONSerialization.data(withJSONObject: payload)
        guard request.httpBody!.count <= 512 * 1_024 else { throw MacLocalMCPError.incompatible }
        return try await fetch(request)
    }
}
#endif
