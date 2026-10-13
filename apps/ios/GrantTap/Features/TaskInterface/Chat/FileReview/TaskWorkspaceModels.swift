import Foundation

struct TaskWorkspaceEntry: Codable, Equatable, Identifiable {
    let path: String
    let name: String
    let kind: String
    var size: Int64? = nil
    var id: String { path }
}

struct TaskWorkspaceQuery: Codable {
    let type = "session.workspace.query"
    let sessionId: String
    let requestId: String
    let mode: String
    let path: String
    let offset: Int
    let createdAt: Double
}

struct TaskWorkspaceSnapshot: Codable, Equatable {
    let type: String
    let sessionId: String
    let requestId: String
    let path: String
    var entries: [TaskWorkspaceEntry]? = nil
    var text: String? = nil
    let truncated: Bool
    var nextOffset: Int? = nil
    var unavailable: Bool? = nil
    let createdAt: Double

    var isWellFormed: Bool {
        guard type == "session.workspace.result", !sessionId.isEmpty, sessionId.count <= 512,
              !requestId.isEmpty, requestId.count <= 128, validPath(path),
              createdAt.isFinite, (nextOffset ?? 1) > 0,
              (entries?.count ?? 0) <= 200, (text?.utf8.count ?? 0) <= 128 * 1_024 else { return false }
        if unavailable == true { return entries == nil && text == nil }
        guard (entries == nil) != (text == nil),
              nextOffset == nil || truncated else { return false }
        return entries?.allSatisfy { entry in
            !entry.path.isEmpty && validPath(entry.path) && !entry.name.isEmpty
                && entry.name.count <= 1_024 && ["directory", "file"].contains(entry.kind)
                && (entry.size ?? 0) >= 0
        } ?? (text != nil)
    }

    private func validPath(_ value: String) -> Bool {
        value.count <= 4_096 && !value.hasPrefix("/") && !value.contains("\\")
            && !value.contains("\u{0}") && !value.split(separator: "/").contains("..")
    }
}
