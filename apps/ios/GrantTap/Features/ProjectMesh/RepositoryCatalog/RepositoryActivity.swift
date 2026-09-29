import Foundation

enum RepositoryActivity {
    static func currentTasks(_ entry: RepositoryCatalog.Entry) -> [RepositoryCatalog.TaskReference] {
        entry.memberships.flatMap(\.tasks).filter { $0.relation == .current }
    }

    static func working(_ entry: RepositoryCatalog.Entry) -> Int {
        currentTasks(entry).filter { $0.row.state == "working" && $0.row.execution?.endedAt == nil }.count
    }

    static func summary(_ entry: RepositoryCatalog.Entry) -> String {
        let tasks = currentTasks(entry)
        var parts: [String] = []
        let working = working(entry)
        if working > 0 { parts.append(LPlural(working, one: "%d working", many: "%d working")) }
        let attention = tasks.filter { ["needs_user", "blocked"].contains($0.row.state) }.count
        if attention > 0 { parts.append(LPlural(attention, one: "%d needs you", many: "%d need you")) }
        let known = entry.memberships.flatMap(\.tasks).filter { $0.relation != .previous }
        parts.append(LPlural(Set(known.map(\.id)).count, one: "%d task", many: "%d tasks"))
        let branches = Set(tasks.compactMap { $0.row.execution?.branch }.filter { !$0.isEmpty }).sorted()
        if !branches.isEmpty { parts.append(branches.prefix(3).joined(separator: ", ")) }
        return parts.joined(separator: " · ")
    }
}
