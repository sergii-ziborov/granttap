import Foundation

enum DeliveryPersistence {
    struct Admission {
        let deliveries: [OutgoingDelivery]
        let shouldSend: Bool
    }

    private static let filename = "outgoing-deliveries.json"
    static let maxActiveCount = 32
    /// One extra compact failure row makes a rejected 33rd send visible
    /// without deleting any of the 32 in-flight lifecycles.
    static let maxPersistedCount = maxActiveCount + 1
    static let maxPersistedBytes = 64_000_000
    private static let admissionFailureReserveBytes = 16_000
    static let maxActiveEncodedBytes = maxPersistedBytes - admissionFailureReserveBytes

    private static func isActive(_ delivery: OutgoingDelivery) -> Bool {
        delivery.state == .queued || delivery.state == .sending
    }

    /// Encode the exact JSON array that is written to disk. Encoding each row
    /// independently and adding literal array punctuation preserves every JSON
    /// escape while avoiding repeated 64 MB whole-array encodes.
    static func encodedData(_ deliveries: [OutgoingDelivery]) -> Data? {
        let encoder = JSONEncoder()
        var data = Data([0x5B]) // [
        for (index, delivery) in deliveries.enumerated() {
            guard let row = try? encoder.encode(delivery) else { return nil }
            if index > 0 { data.append(0x2C) } // ,
            data.append(row)
        }
        data.append(0x5D) // ]
        return data
    }

    /// Protect every active lifecycle. Only terminal rows may yield to the
    /// exact count/encoded-byte cap; an impossible active set is returned whole
    /// so callers never mistake silent eviction for successful persistence.
    static func bounded(
        _ deliveries: [OutgoingDelivery],
        maxCount: Int = maxPersistedCount,
        maxEncodedBytes: Int = maxPersistedBytes
    ) -> [OutgoingDelivery] {
        let countBudget = max(0, maxCount)
        let byteBudget = max(0, maxEncodedBytes)
        let encoder = JSONEncoder()
        let rows = deliveries.map { try? encoder.encode($0) }
        let activeIndices = deliveries.indices.filter { isActive(deliveries[$0]) }
        let protected = activeIndices.map { deliveries[$0] }
        guard activeIndices.count <= countBudget,
              activeIndices.allSatisfy({ rows[$0] != nil }),
              let protectedData = encodedData(protected),
              protectedData.count <= byteBudget else {
            return protected
        }

        var selected = Set(activeIndices)
        var encodedBytes = protectedData.count
        for index in deliveries.indices where !selected.contains(index) {
            guard selected.count < countBudget, let row = rows[index] else { continue }
            let addedBytes = row.count + (selected.isEmpty ? 0 : 1)
            guard addedBytes <= byteBudget,
                  encodedBytes <= byteBudget - addedBytes else { continue }
            selected.insert(index)
            encodedBytes += addedBytes
        }
        return deliveries.indices.compactMap { selected.contains($0) ? deliveries[$0] : nil }
    }

    /// Admit newest without ever evicting an older active row. A rejected row
    /// becomes a compact, persisted, non-retryable failure and is never sent.
    static func admit(
        _ newest: OutgoingDelivery,
        into existing: [OutgoingDelivery],
        maxActiveCount: Int = DeliveryPersistence.maxActiveCount,
        maxActiveEncodedBytes: Int = DeliveryPersistence.maxActiveEncodedBytes,
        maxPersistedBytes: Int = DeliveryPersistence.maxPersistedBytes
    ) -> Admission {
        let active = existing.filter(isActive)
        let terminal = existing.filter { !isActive($0) }
        let activeCandidate = [newest] + active
        let activeCandidateBytes = encodedData(activeCandidate)?.count ?? Int.max
        let activeFits = activeCandidate.count <= max(0, maxActiveCount)
            && activeCandidateBytes <= max(0, maxActiveEncodedBytes)
            && activeCandidateBytes <= max(0, maxPersistedBytes)
        if activeFits {
            return Admission(
                deliveries: appendingTerminalRows(
                    required: activeCandidate,
                    optional: terminal,
                    maxCount: max(0, maxActiveCount) + 1,
                    maxEncodedBytes: maxPersistedBytes
                ),
                shouldSend: true
            )
        }

        let activeBytes = encodedData(active)?.count ?? Int.max
        let failureSeparatorBytes = active.isEmpty ? 0 : 1
        let availableFailureBytes: Int = {
            let budget = max(0, maxPersistedBytes)
            guard activeBytes <= budget,
                  failureSeparatorBytes <= budget - activeBytes else { return 0 }
            return budget - activeBytes - failureSeparatorBytes
        }()
        let failure = compactAdmissionFailure(
            from: newest,
            maxEncodedRowBytes: availableFailureBytes
        )
        return Admission(
            deliveries: appendingTerminalRows(
                required: [failure] + active,
                optional: terminal,
                maxCount: max(0, maxActiveCount) + 1,
                maxEncodedBytes: maxPersistedBytes
            ),
            shouldSend: false
        )
    }

    static func load(
        from sourceURL: URL? = nil,
        maxEncodedBytes: Int = DeliveryPersistence.maxPersistedBytes
    ) -> [OutgoingDelivery] {
        let sourceURL = sourceURL ?? fileURL
        let byteBudget = max(0, maxEncodedBytes)
        // URL resource values may cache a previous size for a URL whose file
        // was atomically replaced. Query the filesystem immediately before the
        // read so the preflight limit applies to the current file contents.
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: sourceURL.path),
              attributes[.type] as? FileAttributeType == .typeRegular,
              let fileSize = (attributes[.size] as? NSNumber)?.int64Value,
              fileSize >= 0,
              fileSize <= Int64(byteBudget),
              let data = try? Data(contentsOf: sourceURL, options: .mappedIfSafe),
              data.count <= byteBudget,
              let deliveries = try? JSONDecoder().decode([OutgoingDelivery].self, from: data) else {
            return []
        }
        let sorted = deliveries.sorted { $0.createdAt > $1.createdAt }
        let sortedActiveCount = sorted.filter(isActive).count
        let loadCountBudget = sortedActiveCount > maxActiveCount
            ? sortedActiveCount + 1
            : maxPersistedCount
        let retained = bounded(
            sorted,
            maxCount: loadCountBudget,
            maxEncodedBytes: byteBudget
        )
        let retainedActive = retained.filter(isActive)
        // Older app versions could persist more than today's active count cap.
        // Keep every such lifecycle available for recovery and let it drain;
        // returning an empty outbox would silently lose all pending work.
        if sortedActiveCount > maxActiveCount {
            return retained
        }
        guard retainedActive.count <= maxActiveCount,
              retained.count <= maxPersistedCount,
              let encoded = encodedData(retained), encoded.count <= byteBudget else {
            return []
        }
        return retained
    }

    static func save(_ deliveries: [OutgoingDelivery], to destinationURL: URL? = nil) {
        let activeCount = deliveries.filter(isActive).count
        // The count cap governs new admission. A legacy over-cap outbox must be
        // able to persist each state transition until it drains; otherwise a
        // crash resurrects rows that already reached a terminal state.
        let saveCountBudget = activeCount > maxActiveCount
            ? activeCount + 1
            : maxPersistedCount
        let retained = bounded(deliveries, maxCount: saveCountBudget)
        guard retained.filter(isActive).count == activeCount,
              let data = encodedData(retained), data.count <= maxPersistedBytes else { return }
        let destinationURL = destinationURL ?? fileURL
        do {
            try FileManager.default.createDirectory(at: destinationURL.deletingLastPathComponent(),
                                                    withIntermediateDirectories: true)
            try data.write(to: destinationURL, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        } catch {
            // Delivery state is helpful recovery metadata; a failed persistence
            // write must never prevent the encrypted send itself.
        }
    }

    static func remove() {
        try? FileManager.default.removeItem(at: fileURL)
    }

    private static var directoryURL: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("GrantTap", isDirectory: true)
    }

    private static var fileURL: URL { directoryURL.appendingPathComponent(filename) }

}
