import Foundation

/// Exercises Health while a realistic multi-Mesh archive is refreshed repeatedly.
enum MeshArchiveStreamingFixture {
    @MainActor
    static func apply(to model: AppModel) {
        #if DEBUG
        guard ProcessInfo.processInfo.environment["GRANTTAP_TEST_MESH_STREAM"] == "1" else { return }
        let files = (0..<64).map { file in
            ProjectCodeMap.File(path: "Sources/Module\(file).swift", language: "swift", lineCount: 240,
                symbols: (0..<12).map { symbol in
                    .init(id: "\(file)-\(symbol)", label: "RecordedDeclaration\(symbol)", kind: "function",
                          startLine: symbol * 10 + 1, lineCount: 8)
                })
        }
        let map = ProjectCodeMap(files: files, roads: [], totalFiles: files.count, truncated: false)
        for index in 0..<48 {
            let id = "archive-stream-\(index)"
            var graph = ProjectRepositoryGraph(projectId: id, repositoryId: "fixture:\(index)",
                revision: "fixture", weavatrixVersion: "2.17.4", analysisStatus: "COMPLETE",
                nodes: [], relations: [], totalNodes: 0, totalRelations: 0, truncated: false)
            graph.codeMap = map
            model.meshSnapshots[id] = ProjectMeshSnapshot(type: "mesh.snapshot", sessionId: id,
                projectId: id, project: .init(projectId: id, name: "Archive fixture \(index)",
                    canonicalRepositoryId: "fixture:\(index)", createdAt: 1),
                repositoryGraphs: [graph], tasks: [], executions: [], claims: [], dependencies: [],
                events: [], generatedAt: 1)
        }
        Task { @MainActor [weak model] in
            for revision in 0..<600 {
                guard let model, model.demoMode else { return }
                model.meshAttentionStates["archive-stream"] = .init(status: .acknowledged,
                    createdAt: 1, updatedAt: Double(revision))
                model.persistMeshState()
                do { try await Task.sleep(nanoseconds: 150_000_000) } catch { return }
            }
        }
        #endif
    }
}
