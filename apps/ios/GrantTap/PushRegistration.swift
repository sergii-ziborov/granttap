import Foundation
import UIKit

@MainActor
protocol PushRegistrationTransport {
    func data(for request: URLRequest) async throws -> (Data, URLResponse)
}

extension URLSession: PushRegistrationTransport {}

@MainActor
final class PushRegistrationManager: ObservableObject {
    static let shared = PushRegistrationManager()

    enum State: Equatable {
        case idle, registering, active(Int), unavailable(String), failed(String)
    }

    @Published private(set) var state: State = .idle
    private var deviceToken: String?
    private let model: AppModel
    private let transport: PushRegistrationTransport

    init(
        model: AppModel? = nil, transport: PushRegistrationTransport? = nil,
        initialState: State = .idle
    ) {
        self.model = model ?? .shared
        self.transport = transport ?? URLSession.shared
        self.state = initialState
    }

    func didRegister(deviceToken data: Data) {
        // Apple explicitly says not to persist APNs tokens; request a current one
        // on every launch and retain it in memory only.
        deviceToken = data.map { String(format: "%02x", $0) }.joined()
        registerCurrentPairing()
    }

    func didFail(_ error: Error) {
        state = .failed(error.localizedDescription)
        AuditStore.shared.record("push", detail: "APNs registration failed", outcome: "failed")
    }

    func pairingDidChange() { registerCurrentPairing() }

    func registerAgain() {
        registerAgain { UIApplication.shared.registerForRemoteNotifications() }
    }

    func registerAgain(requestSystemToken: () -> Void) {
        state = .registering
        requestSystemToken()
        if deviceToken != nil { registerCurrentPairing() }
    }

    func registerCurrentPairing() {
        guard let token = deviceToken else {
            state = .registering
            return
        }
        let links = model.connectionRegistry.connections
        guard !links.isEmpty else { state = .idle; return }
        state = .registering
        Task {
            var anyEnabled = false
            var lastDevices = 0
            var lastError: String?
            for conn in links {
                let pairing = conn.pairing
                guard let auth = pairing.pushAuth, !auth.isEmpty else { continue }
                guard let url = endpoint(pairing, path: "/push/register") else { continue }
                do {
                    var request = URLRequest(url: url)
                    request.httpMethod = "PUT"
                    request.setValue("Bearer \(auth)", forHTTPHeaderField: "Authorization")
                    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                    request.httpBody = try JSONSerialization.data(withJSONObject: [
                        "token": token,
                        "environment": Self.apnsEnvironment,
                        "bundleId": Bundle.main.bundleIdentifier ?? "com.ziborov.granttap",
                    ])
                    let (data, response) = try await transport.data(for: request)
                    let status = (response as? HTTPURLResponse)?.statusCode ?? 0
                    guard status == 200 else { throw PushError.http(status) }
                    let body = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
                    lastDevices = body?["devices"] as? Int ?? 1
                    if body?["enabled"] as? Bool ?? false { anyEnabled = true }
                } catch {
                    lastError = error.localizedDescription
                }
            }
            if anyEnabled {
                state = .active(max(lastDevices, 1))
                AuditStore.shared.record("push", detail: "APNs registered for \(links.count) link(s)")
            } else if links.contains(where: { ($0.pairing.pushAuth ?? "").isEmpty }) {
                state = .unavailable(L("Pair again to enable background delivery."))
            } else if let lastError {
                state = .failed(lastError)
                AuditStore.shared.record("push", detail: "Relay push registration failed", outcome: "failed")
            } else {
                state = .unavailable(L("The relay has no APNs provider key."))
            }
        }
    }

    func unregister(_ pairing: Pairing) {
        guard let token = deviceToken, let auth = pairing.pushAuth,
              let url = endpoint(pairing, path: "/push/register") else { return }
        Task {
            var request = URLRequest(url: url)
            request.httpMethod = "DELETE"
            request.setValue("Bearer \(auth)", forHTTPHeaderField: "Authorization")
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try? JSONSerialization.data(withJSONObject: [
                "token": token, "environment": Self.apnsEnvironment,
                "bundleId": Bundle.main.bundleIdentifier ?? "com.ziborov.granttap",
            ])
            _ = try? await transport.data(for: request)
        }
    }

    func endpoint(_ pairing: Pairing, path: String) -> URL? {
        guard var components = URLComponents(string: pairing.relayUrl) else { return nil }
        guard let scheme = components.scheme?.lowercased(),
              ["wss", "ws", "https", "http"].contains(scheme) else { return nil }
        if components.scheme == "wss" { components.scheme = "https" }
        if components.scheme == "ws" { components.scheme = "http" }
        components.path = path
        components.queryItems = [URLQueryItem(name: "room", value: pairing.room)]
        return components.url
    }

    /// Mirror packages/core/background-wake resolveApnsEnvironment: prefer the
    /// signed aps-environment, then DEBUG → sandbox / Release → production.
    static func resolveApnsEnvironment(_ aps: String?, fallback: String) -> String {
        if let aps {
            let raw = aps.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            if raw == "production" || raw == "prod" { return "production" }
            if raw == "development" || raw == "sandbox" || raw == "dev" { return "sandbox" }
        }
        return fallback
    }

    static var apnsEnvironment: String {
        #if DEBUG
        let fallback = "sandbox"
        #else
        let fallback = "production"
        #endif
        return resolveApnsEnvironment(
            Bundle.main.object(forInfoDictionaryKey: "APSEnvironment") as? String,
            fallback: fallback
        )
    }
}


private enum PushError: LocalizedError {
    case http(Int)
    var errorDescription: String? {
        switch self { case .http(let status): return "Push registration returned HTTP \(status)" }
    }
}
