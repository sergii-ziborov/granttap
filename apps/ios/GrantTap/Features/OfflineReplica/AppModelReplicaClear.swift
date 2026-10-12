import Foundation

@MainActor
extension AppModel {
    /// Settings → Clear local chat cache (does not affect Mac sessions).
    func clearLocalSessionCache() {
        replicaGeneration = UUID()
        transcriptBackfill = TranscriptBackfill()
        replicaImageTask?.cancel()
        replicaImageTask = nil
        replicaImageQueue = []
        replicaImageRetryAt = [:]
        for read in replicaImageReads.values { read.cancel() }
        replicaImageReads = [:]
        replicaImageTransfer.cancel()
        SessionCatalogCache.clear()
        SessionActivityPersistence.clear()
        ReplicaImageStore.shared.clear()
        ProjectMeshPersistence.clear()
        ProjectGovernancePersistence.clear()
        meshSnapshots = [:]
        projectGovernance = [:]
        localMeshProjectIds = []
        pendingMeshEvents = []
        meshAttentionStates = [:]
        meshProjectSourceRooms = [:]
        meshEventSourceRooms = [:]
        sessions = []
        sessionHistory = []
        activities = [:]
        replicaSessionIndex = [:]
        lastSessionsGeneratedAt = 0
        append("catalog-cache: cleared")
        AuditStore.shared.record("cache", detail: "Cleared local conversations, images and Mesh copy")
        pushToWatch()
        // Awaitable refresh so Active repopulates from THIS Mac's lean publish.
        Task { await refreshSessions() }
    }

}
