import Foundation

/// Serializes whole Mesh archives without losing questions or routing state.
final class ProjectMeshArchiveWriter {
    private let queue = DispatchQueue(label: "com.ziborov.granttap.mesh-archive", qos: .utility)
    private let lock = NSLock()
    private var pending: ProjectMeshArchive?
    private let write: (ProjectMeshArchive) -> Void

    init(write: @escaping (ProjectMeshArchive) -> Void) { self.write = write }

    func enqueue(_ archive: ProjectMeshArchive) {
        lock.lock()
        pending = archive
        queue.async { self.drain() }
        lock.unlock()
    }

    /// Explicit reads and cleanup see all state accepted before the barrier.
    func barrier<T>(_ action: () throws -> T) rethrows -> T { try queue.sync(execute: action) }
    func finish(_ completion: @escaping () -> Void) { queue.async(execute: completion) }

    private func drain() {
        lock.lock()
        let archive = pending
        pending = nil
        lock.unlock()
        if let archive { write(archive) }
    }
}
