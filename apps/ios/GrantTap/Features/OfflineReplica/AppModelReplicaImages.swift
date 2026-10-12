import Foundation

struct ReplicaImageJob: Codable, Equatable {
    let sessionId: String
    let imageId: String
    let cursor: String?
}

@MainActor
extension AppModel {
    func imageConversation(forEntryId id: String) -> String? {
        let matches = activities.values.filter { activity in
            activity.entries.contains { $0.id == id || ($0.images ?? []).contains { $0.id == id } }
        }
        return matches.count == 1 ? matches.first?.sessionId : nil
    }

    func imageStorageScope(_ sessionId: String) -> String {
        if case .exact(let room) = sessionRoomOwnership(forSessionId: sessionId) {
            if let connection = connectionRegistry.connections.first(where: { $0.id == room }),
               let account = connection.linkedAccountId, let machine = connection.linkedMachineId {
                return account + ":" + machine
            }
            return room
        }
        return "local-mac"
    }

    func messageImageData(sessionId: String, imageId: String, cursor: String? = nil) async throws -> Data {
        if case .ambiguous = sessionRoomOwnership(forSessionId: sessionId) {
            throw ReplicaImageTransfer.TransferError.unavailable
        }
        let scope = imageStorageScope(sessionId)
        if let saved = cachedMessageImage(sessionId: sessionId, imageId: imageId) { return saved }
        let readId = scope + "\u{0}" + sessionId + "\u{0}" + imageId
        if let running = replicaImageReads[readId] { return try await running.value }
        let generation = replicaGeneration
        let work = Task { try await self.readMessageImage(sessionId: sessionId, imageId: imageId,
                                                         cursor: cursor, generation: generation) }
        replicaImageReads[readId] = work
        defer { if replicaGeneration == generation { replicaImageReads.removeValue(forKey: readId) } }
        return try await work.value
    }

    private func readMessageImage(sessionId: String, imageId: String, cursor: String?,
                                  generation: UUID) async throws -> Data {
        let scope = imageStorageScope(sessionId)
        let store = ReplicaImageStore.shared
        let oldRoom = sourceRoom(forSessionId: sessionId)
        let pageCursor = cursor ?? store.cursor(scope: scope, sessionId: sessionId, imageId: imageId)
            ?? oldRoom.flatMap { store.cursor(scope: $0, sessionId: sessionId, imageId: imageId) }
        let bytes: Data
        #if targetEnvironment(macCatalyst)
        if let session = (sessions + sessionHistory).first(where: { $0.sessionId == sessionId }),
           usesLocalMCP(for: session), let reader = localMCPReader {
            bytes = try await reader.image(for: session, imageId: imageId, cursor: pageCursor)
        } else {
            guard let client = relayForSession(sessionId) else { throw ReplicaImageTransfer.TransferError.unavailable }
            bytes = try await replicaImageTransfer.data(sessionId: sessionId, imageId: imageId, cursor: pageCursor, client: client)
        }
        #else
        guard let client = relayForSession(sessionId) else { throw ReplicaImageTransfer.TransferError.unavailable }
        bytes = try await replicaImageTransfer.data(sessionId: sessionId, imageId: imageId, cursor: pageCursor, client: client)
        #endif
        try Task.checkCancellation()
        guard generation == replicaGeneration, MessageImageLoader.thumbnail(bytes) != nil else {
            throw ReplicaImageTransfer.TransferError.invalid
        }
        try store.save(bytes, scope: scope, sessionId: sessionId, imageId: imageId)
        replicaImagesRevision &+= 1
        return bytes
    }

    func cachedMessageImage(sessionId: String, imageId: String) -> Data? {
        let store = ReplicaImageStore.shared
        let scope = imageStorageScope(sessionId)
        if let bytes = store.load(scope: scope, sessionId: sessionId, imageId: imageId) { return bytes }
        // A verified account link can replace this same QR route's storage scope.
        guard let room = sourceRoom(forSessionId: sessionId), room != scope,
              let bytes = store.load(scope: room, sessionId: sessionId, imageId: imageId) else { return nil }
        try? store.save(bytes, scope: scope, sessionId: sessionId, imageId: imageId)
        return bytes
    }

    func enqueueReplicaImages(_ activity: SessionActivity) {
        let jobs = activity.entries.flatMap { entry in
            let ids = (entry.images ?? []).filter(\.isValid).map(\.id)
                + (entry.attachments?.contains("Image") == true ? [entry.id] : [])
            return ids.map { ReplicaImageJob(sessionId: activity.sessionId, imageId: $0,
                                            cursor: activity.history?.requestedCursor) }
        }
        for job in jobs where !replicaImageQueue.contains(where: {
            $0.sessionId == job.sessionId && $0.imageId == job.imageId
        }) {
            ReplicaImageStore.shared.remember(job, scope: imageStorageScope(job.sessionId))
            let key = job.sessionId + "\u{0}" + job.imageId
            guard (replicaImageRetryAt[key] ?? 0) < Date().timeIntervalSince1970,
                  cachedMessageImage(sessionId: job.sessionId, imageId: job.imageId) == nil else { continue }
            replicaImageQueue.append(job)
        }
        guard replicaImageTask == nil, !replicaImageQueue.isEmpty else { return }
        let generation = replicaGeneration
        replicaImageTask = Task { [weak self] in
            guard let self else { return }
            defer { if generation == replicaGeneration { replicaImageTask = nil } }
            while !replicaImageQueue.isEmpty, !Task.isCancelled, generation == replicaGeneration {
                let job = replicaImageQueue[0]
                do { _ = try await messageImageData(sessionId: job.sessionId, imageId: job.imageId) }
                catch {
                    if generation == replicaGeneration {
                        replicaImageRetryAt[job.sessionId + "\u{0}" + job.imageId] = Date().timeIntervalSince1970 + 30
                    }
                }
                guard generation == replicaGeneration else { return }
                replicaImageQueue.removeFirst()
            }
        }
    }
}
