import Foundation

enum ReplicaImageRetention: Int, CaseIterable {
    case week = 7, month = 30, quarter = 90, unlimited = 0
    static let settingsKey = "granttap.image-cache.retention-days"
    static let maximumBytes: Int64 = 256 * 1_024 * 1_024

    static var current: Self {
        let saved = UserDefaults.standard.object(forKey: settingsKey) as? Int
        return saved.flatMap(Self.init(rawValue:)) ?? .month
    }

    var title: String {
        switch self {
        case .week: return L("7 days")
        case .month: return L("30 days")
        case .quarter: return L("90 days")
        case .unlimited: return L("Until cache is full")
        }
    }
}

extension ReplicaImageStore {
    /// Runs on startup, policy changes and writes. Only downloaded media and
    /// bounded page locators live here; pairings and pending sends are separate.
    @discardableResult
    func prune(now: Date = Date(), retention: ReplicaImageRetention = .current,
               maximumBytes: Int64 = ReplicaImageRetention.maximumBytes) -> Int {
        let urls = (try? FileManager.default.contentsOfDirectory(at: directory,
            includingPropertiesForKeys: [.fileSizeKey, .contentModificationDateKey])) ?? []
        let records = urls.compactMap { url -> (URL, Int64, Date)? in
            guard let values = try? url.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey])
            else { return nil }
            return (url, Int64(values.fileSize ?? 0), values.contentModificationDate ?? .distantPast)
        }.sorted { $0.2 < $1.2 }
        var total = records.reduce(Int64(0)) { $0 + $1.1 }
        var removed = 0
        for (url, size, accessed) in records {
            let expired = ["image", "document", "names"].contains(url.pathExtension) && retention != .unlimited
                && now.timeIntervalSince(accessed) > Double(retention.rawValue) * 86_400
            // Keep tiny page locators after evicting bytes, within the same cap.
            guard expired || total > max(0, maximumBytes) else { continue }
            do {
                try FileManager.default.removeItem(at: url)
                total -= size
                removed += 1
            } catch { continue }
        }
        return removed
    }
}
