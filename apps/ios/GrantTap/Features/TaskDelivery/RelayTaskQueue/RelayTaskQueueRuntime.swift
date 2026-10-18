import Foundation

@MainActor
extension AppModel {
    func resumeRelayTaskQueues(immediate: Bool = false) {
        if immediate {
            relayQueueNeedsSync = true
            relayQueueDelay?.cancel()
            if !demoMode { Task { @MainActor [weak self] in await self?.uploadNewRelayTaskQueues() } }
        }
        guard !demoMode, relayQueueLoop == nil,
              deliveries.contains(where: RelayTaskQueueSchedule.needsSync) else { return }
        let generation = UUID()
        relayQueueLoopGeneration = generation
        relayQueueLoop = Task { @MainActor [weak self] in
            repeat {
                self?.relayQueueNeedsSync = false
                await self?.synchronizeRelayTaskQueues()
                guard let rows = self?.deliveries, rows.contains(where: RelayTaskQueueSchedule.needsSync) else { break }
                if self?.relayQueueNeedsSync == true { continue }
                let seconds = RelayTaskQueueSchedule.delaySeconds(rows, now: Date().timeIntervalSince1970 * 1_000)
                let delay = Task<Void, Never> { try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000)) }
                self?.relayQueueDelay = delay
                await delay.value
            } while !Task.isCancelled
            if self?.relayQueueLoopGeneration == generation {
                self?.relayQueueDelay = nil
                self?.relayQueueLoop = nil
                self?.relayQueueLoopGeneration = nil
            }
        }
    }

    func synchronizeRelayTaskQueues(session: URLSession = .shared) async {
        guard !relayQueueSyncInProgress else { return }
        relayQueueSyncInProgress = true
        defer { relayQueueSyncInProgress = false }
        let ids = RelayTaskQueueSchedule.syncOrder(deliveries)
        for id in ids { await synchronizeRelayTaskQueueRow(id, session: session) }
    }

    func uploadNewRelayTaskQueues(session: URLSession = .shared) async {
        let ids = RelayTaskQueueSchedule.syncOrder(deliveries).filter { id in
            deliveries.first { $0.id == id }?.relayJob?.serverState == nil
        }
        for id in ids { await synchronizeRelayTaskQueueRow(id, session: session) }
    }

    private func synchronizeRelayTaskQueueRow(_ id: String, session: URLSession) async {
        guard relayQueueOperations[id] == nil else { return }
        let generation = UUID()
        relayQueueOperations[id] = generation
        defer {
            if relayQueueOperations[id] == generation { relayQueueOperations.removeValue(forKey: id) }
        }
        guard !Task.isCancelled, let row = deliveries.first(where: { $0.id == id }) else { return }
        guard row.awaitingSessionRemap != true || row.continuationOriginId != nil else { return }
        #if targetEnvironment(macCatalyst)
        if row.chatQueue?.transport == .localMCP {
            do { try await synchronizeLocalRelayTaskQueue(id) }
            catch { setRelayTaskQueueError(id, error.localizedDescription) }
            return
        }
        #endif
        guard let room = row.roomId,
              let connection = connectionRegistry.connections.first(where: { $0.id == room }),
              connection.pairing.pushAuth?.isEmpty == false, !connection.pairing.isHub else {
            setRelayTaskQueueError(id, RelayTaskQueueError.unavailable.localizedDescription)
            return
        }
        let transport = RelayTaskQueueTransport(pairing: connection.pairing,
            address: relaysByRoom[room]?.resolvedRelayURL, session: session)
        do {
            if row.chatQueue?.cancelRequested == true {
                try await reconcileRelayTaskQueueCancellation(id, transport: transport)
            } else {
                try await synchronizeRelayTaskQueue(id, pairing: connection.pairing, transport: transport)
            }
        } catch {
            setRelayTaskQueueError(id, error.localizedDescription)
        }
    }

    private func synchronizeRelayTaskQueue(_ id: String, pairing: Pairing,
                                          transport: RelayTaskQueueTransport) async throws {
        guard var row = deliveries.first(where: { $0.id == id }) else { return }
        if row.relayJob == nil {
            let message = relayQueuedMessage(for: row)
            let due = row.chatQueue?.notBefore ?? row.createdAt
            let created = floor(row.chatQueue?.queuedAt ?? row.createdAt)
            let sendImmediately = row.chatQueue?.sendImmediately == true
            let reservation = try await Task.detached(priority: .utility) {
                let prepared = try RelayTaskQueueEncoding.prepare(message, pairing: pairing, notBefore: due,
                    now: created, sendImmediately: sendImmediately)
                return try RelayTaskQueueCipherStore.save(prepared)
            }.value
            guard let index = deliveries.firstIndex(where: { $0.id == id }) else { return }
            deliveries[index].relayJob = reservation
            persistDeliveries()
            row = deliveries[index]
        }
        if row.chatQueue?.cancelRequested == true {
            try await reconcileRelayTaskQueueCancellation(id, transport: transport)
            return
        }
        guard let reservation = row.relayJob else { return }
        if reservation.serverState == nil {
            guard let index = deliveries.firstIndex(where: { $0.id == id }) else { return }
            deliveries[index].relayJob?.uploadAttempted = true
            persistDeliveries()
            applyRelayTaskQueueReceipt(try await transport.upload(reservation), to: id)
        } else {
            applyRelayTaskQueueReceipt(try await transport.receipt(id), to: id)
        }
    }

    func applyRelayTaskQueueReceipt(_ receipt: RelayTaskJobReceipt, to id: String) {
        guard receipt.id == id, let index = deliveries.firstIndex(where: { $0.id == id }),
              deliveries[index].chatQueue?.relayManaged == true else { return }
        if receipt.state == .cancelled {
            finishRelayTaskQueueCancellation(at: index)
            return
        }
        let state: DeliveryState = switch receipt.state {
        case .queued: .queued
        case .accepted: .sending
        case .completed: .delivered
        default: .failed
        }
        let error = RelayTaskQueueStatus.failure(receipt)
        let newlyStored = [.queued, .accepted, .completed].contains(receipt.state)
            && deliveries[index].chatQueue?.waiting == false && deliveries[index].relayStoredAt == nil
        guard deliveries[index].relayJob?.serverState != receipt.state
            || deliveries[index].relayJob?.resultCode != receipt.resultCode
            || deliveries[index].state != state || deliveries[index].error != error || newlyStored else { return }
        if newlyStored { deliveries[index].relayStoredAt = Date().timeIntervalSince1970 * 1_000 }
        deliveries[index].relayJob?.serverState = receipt.state
        deliveries[index].relayJob?.resultCode = receipt.resultCode
        deliveries[index].state = state
        deliveries[index].error = error
        deliveries[index].updatedAt = floor(Date().timeIntervalSince1970 * 1_000)
        if receipt.state == .accepted || receipt.state == .completed {
            appendQueuedMessageToTranscript(deliveries[index])
        }
        if receipt.state == .completed {
            deliveries[index].chatQueue?.waiting = false
            deliveries[index].relayJob?.envelope = nil
            Task.detached(priority: .utility) { RelayTaskQueueCipherStore.remove(id) }
        }
        persistDeliveries()
    }

    func setRelayTaskQueueError(_ id: String, _ message: String) {
        guard let index = deliveries.firstIndex(where: { $0.id == id }),
              deliveries[index].error != message else { return }
        deliveries[index].error = message
        persistDeliveries()
    }
}
