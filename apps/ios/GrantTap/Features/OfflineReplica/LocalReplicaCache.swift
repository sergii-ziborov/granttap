import Foundation

enum LocalReplicaCache {
    static var bytes: Int64 {
        let root = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("GrantTap")
        let files = ["sessions-catalog.sqlite", "project-mesh.json", "project-governance-cache.json"]
        return SessionActivityPersistence.bytes + ReplicaImageStore.shared.bytes + files.reduce(0) {
            $0 + Int64((try? root.appendingPathComponent($1)
                .resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0)
        }
    }
}
