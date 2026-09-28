#if targetEnvironment(macCatalyst)
import Foundation
import SwiftUI

struct MacProviderReadiness: Decodable, Sendable {
    let id: String
    let status: String
    let detail: String
    let hooks: [ProviderHookInfo]?
    let hooksCheckedAt: Double?
}

extension MacLocalMCPModel {
    func trustHook(_ request: ProviderHookTrust) async throws -> ProviderHookTrustResult {
        guard let socket = status?.desktopEngineSocket, request.endpointId == status?.endpointId else {
            throw MacLocalMCPError.unavailable
        }
        let data = try await MacLocalMCPClient.read(socketPath: socket, operation: "desktop.codex_hook_trust",
            input: ["endpointId": request.endpointId, "event": request.event, "key": request.key,
                    "currentHash": request.currentHash, "requestId": request.requestId,
                    "createdAt": String(request.createdAt)])
        let result = try JSONDecoder().decode(ProviderHookTrustResult.self, from: data)
        guard result.requestId == request.requestId, result.endpointId == request.endpointId,
              result.hooks.count <= 2 else { throw MacLocalMCPError.incompatible }
        return result
    }
}
struct MacProviderHooksView: View {
    @ObservedObject var reader: MacLocalMCPModel
    var body: some View {
        ProviderHookReviewView(room: "local-mac", endpointId: reader.status?.endpointId,
            computer: reader.status?.computer ?? L("This Mac"),
            localHooks: reader.status?.providers?.first { $0.id == "codex" }?.hooks)
    }
}
#endif
