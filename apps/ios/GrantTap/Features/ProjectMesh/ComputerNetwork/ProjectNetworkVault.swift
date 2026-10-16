import CryptoKit
import Foundation

enum ProjectNetworkVault {
    static func load(_ projectId: String) -> ProjectNetworkPlan? {
        guard let data = KeychainPairing.load(service: service(projectId)), data.count < 256_000,
              let value = try? JSONDecoder().decode(ProjectNetworkPlan.self, from: data),
              value.projectId == projectId else { return nil }
        return value
    }

    static func save(_ plan: ProjectNetworkPlan) throws {
        let data = try JSONEncoder().encode(plan)
        guard data.count < 256_000, KeychainPairing.save(data, service: service(plan.projectId)) else {
            throw ProjectNetworkError.secureStorage
        }
    }

    private static func service(_ projectId: String) -> String {
        let digest = SHA256.hash(data: Data(projectId.utf8)).map { String(format: "%02x", $0) }.joined()
        return "com.ziborov.granttap.project-network.\(digest)"
    }
}
