#if targetEnvironment(macCatalyst)
import Foundation

private struct MacLocalSnapshotsEnvelope: Decodable {
    let operation: String
    let snapshots: [ProjectMeshSnapshot]
}

extension MacLocalMCPClient {
    static func meshSnapshots(socketPath: String) async throws -> [String: ProjectMeshSnapshot] {
        let data = try await read(socketPath: socketPath,
                                  operation: "desktop.mesh_snapshots", input: nil)
        let envelope = try JSONDecoder().decode(MacLocalSnapshotsEnvelope.self, from: data)
        guard envelope.operation == "desktop.mesh_snapshots",
              envelope.snapshots.count <= 256,
              envelope.snapshots.allSatisfy({ $0.type == "mesh.snapshot"
                  && $0.sessionId == $0.projectId
                  && $0.project.projectId == $0.projectId }) else {
            throw MacLocalMCPError.incompatible
        }
        let rows = Dictionary(envelope.snapshots.map { ($0.projectId, $0) },
                              uniquingKeysWith: { first, _ in first })
        guard rows.count == envelope.snapshots.count else { throw MacLocalMCPError.incompatible }
        return rows
    }
}
#endif
