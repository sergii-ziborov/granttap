import Foundation

@MainActor
extension AppModel {
    func requestProjectGraphAnalysis(projectId: String) async -> ProjectGraphRefreshResult {
        guard meshSnapshots[projectId] != nil else { return .noRoute }
        if projectGraphRequests[projectId]?.pending == true { return .requested }
        let started = Date().timeIntervalSince1970 * 1_000
        projectGraphAttemptAt[projectId] = started
        let request = ProjectGraphRequest(createdAt: started)
        projectGraphRequests[projectId] = request
        var localAvailable = false
        var localRoom: String?
        #if targetEnvironment(macCatalyst)
        if let reader = localMCPReader, reader.isReady,
           reader.meshSnapshots[projectId] != nil {
            // Refresh also repairs stale bindings. Requiring an already-available
            // binding here made exactly those Mesh spaces impossible to rebuild.
            localAvailable = true
            if let endpoint = reader.status?.endpointId {
                localRoom = meshComputerRoomByEndpointId[endpoint]
            }
        }
        #endif
        let plan = ProjectGraphRefreshPlan.make(
            localProjectAvailable: localAvailable,
            sourceRooms: meshProjectSourceRooms[projectId] ?? [],
            connectedRooms: Set(relaysByRoom.keys), localRoom: localRoom
        )
        let result = await plan.execute(localRefresh: {
            #if targetEnvironment(macCatalyst)
            guard let reader = self.localMCPReader else { return false }
            let result = try await reader.enrichedMesh(projectId: projectId, refreshGraph: true)
            self.refreshMacCombinedCatalog()
            return ProjectInsightReports.reports(result).contains { $0.analysisStatus != "UNAVAILABLE" }
            #else
            return false
            #endif
        }, remoteRefresh: { room in
            guard let relay = self.relaysByRoom[room] else { throw URLError(.notConnectedToInternet) }
            try await withCheckedThrowingContinuation { (completion: CheckedContinuation<Void, Error>) in
                relay.requestProjectGraphAnalysis(projectId, requestId: request.requestId) { error in
                    if let error { completion.resume(throwing: error) } else { completion.resume() }
                }
            }
        })
        if projectGraphRequests[projectId]?.pending == false {
            return projectGraphRequests[projectId]?.result ?? result
        }
        projectGraphRequests[projectId]?.result = result
        projectGraphRequests[projectId]?.pending = result == .requested
        if result == .requested {
            Task { [weak self] in
                try? await Task.sleep(nanoseconds: 150_000_000_000)
                guard let self, self.projectGraphRequests[projectId]?.createdAt == started,
                      self.projectGraphRequests[projectId]?.pending == true else { return }
                self.projectGraphRequests[projectId]?.pending = false
                self.projectGraphRequests[projectId]?.result = .failed
            }
        }
        return result
    }

    /// Selected Mesh enrichment is asynchronous; keep observing until the view leaves.
    func observeProjectInsights(projectId: String) async {
        ensureProjectGraphAnalysis(projectId: projectId)
        var first = true
        repeat {
            await refreshProjectInsights(projectId: projectId, requestRemote: first)
            first = false
            do { try await Task.sleep(nanoseconds: 10_000_000_000) } catch { return }
        } while !Task.isCancelled
    }

    func ensureProjectGraphAnalysis(projectId: String) {
        guard let snapshot = meshSnapshots[projectId],
              ProjectInsightReports.needsAnalysis(snapshot),
              projectGraphRequests[projectId]?.pending != true,
              Date().timeIntervalSince1970 * 1_000 - (projectGraphAttemptAt[projectId] ?? 0) > 300_000 else { return }
        Task { [weak self] in _ = await self?.requestProjectGraphAnalysis(projectId: projectId) }
    }

    func refreshProjectInsights(projectId: String, requestRemote: Bool = false) async {
        #if targetEnvironment(macCatalyst)
        if let reader = localMCPReader, reader.isReady, reader.meshSnapshots[projectId] != nil {
            async let graph = try? reader.enrichedMesh(projectId: projectId)
            async let load: Void = reader.refreshMachineLoad()
            if let socket = reader.status?.desktopEngineSocket { await reader.refreshUsage(socketPath: socket) }
            _ = await (graph, load)
            if let sample = reader.machineLoad, sample.isValid {
                recordMachineLoad(sample.wireLoad, fromRoom: "local-mac")
            }
            refreshMacCombinedCatalog()
        }
        #endif
        if requestRemote {
            for room in meshProjectSourceRooms[projectId] ?? [] {
                relaysByRoom[room]?.requestSessionsRefresh()
            }
        }
    }
}
