import Foundation

/// Machine-scoped credential sent only inside an authenticated QR pairing room.
struct AccountMachineLink: Codable {
    let type: String
    let accountId: String
    let machineId: String
    let machineToken: String
    let createdAt: Double

    init(accountId: String, machineId: String, machineToken: String, createdAt: Double) {
        type = "account.machine.link"
        self.accountId = accountId
        self.machineId = machineId
        self.machineToken = machineToken
        self.createdAt = createdAt
    }
}

extension AccountRecovery {
    static func register(_ computer: LinkedComputer, session: GrantTapAccountSession,
                         transport: URLSession = .shared) async throws -> AccountMachineCredential {
        let name = String(computer.displayName.prefix(80))
        let response = try await GrantTapAccountAPI.json(
            "machines", method: "POST", body: ["name": name],
            token: session.token, transport: transport
        )
        guard let id = response["id"] as? String, UUID(uuidString: id) != nil,
              let token = response["machineToken"] as? String,
              token.range(of: "^[A-Za-z0-9_-]{43}$", options: .regularExpression) != nil else {
            throw AccountBridgeError.invalidResponse
        }
        return AccountMachineCredential(accountId: session.accountId,
                                        machineId: id, machineToken: token)
    }
}
