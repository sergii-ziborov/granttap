import Foundation

enum TaskFileEditPath {
    static func relative(_ path: String, session: SessionInfo) -> String? {
        var result = path
        if path.hasPrefix("/") {
            guard let root = session.worktree ?? session.cwd else { return nil }
            let prefix = root.hasSuffix("/") ? root : root + "/"
            guard path.hasPrefix(prefix) else { return nil }
            result = String(path.dropFirst(prefix.count))
        }
        guard !result.isEmpty, result.count <= 4_096, !result.contains("\\"), !result.contains("\0"),
              !result.split(separator: "/").contains("..") else { return nil }
        return result
    }
}
