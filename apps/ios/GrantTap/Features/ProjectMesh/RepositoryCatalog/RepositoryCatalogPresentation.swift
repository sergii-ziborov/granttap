import Foundation

enum RepositoryCatalogPresentation {
    static func identity(_ entry: RepositoryCatalog.Entry) -> String {
        entry.id.hasPrefix("local:") ? L(entry.isGit ? "Local Git repository" : "Workspace without confirmed Git") : entry.id
    }

    static func membership(_ member: RepositoryCatalog.Membership) -> String {
        var parts: [String] = []
        if member.primary { parts.append(L("Primary Mesh repository")) }
        if member.bound { parts.append(L("Bound to this Mesh")) }
        if member.mapped { parts.append(L("Reported in the code map")) }
        if member.observed { parts.append(L("Observed in chat executions")) }
        return parts.joined(separator: " · ")
    }

    static func relation(_ reference: RepositoryCatalog.TaskReference, repositoryId: String) -> String {
        let key: String
        switch reference.relation {
        case .current: key = "Task repository"
        case .lastObserved: key = "Last observed repository"
        case .previous: key = "Previous execution"
        case .multiple: key = "Multiple repositories reported"
        case .unassigned: key = "No repository reported"
        }
        let branch = reference.row.execution.flatMap { execution in
            execution.repositoryId == repositoryId ? execution.branch : nil
        }?.trimmingCharacters(in: .whitespacesAndNewlines)
        return [L(key), branch?.isEmpty == false ? branch : nil].compactMap { $0 }.joined(separator: " · ")
    }

    static func taskContext(task: ProjectMeshTask, snapshot: ProjectMeshSnapshot) -> String {
        let assignment = ProjectTaskRepositoryGroups.assignment(task: task, snapshot: snapshot)
        guard !assignment.repositoryIds.isEmpty else { return L("No repository reported") }
        let names = assignment.repositoryIds.map { repository in
            repository.hasPrefix("local:") ? ProjectOtherSide.displayName(of: repository, in: snapshot) : repository
        }
        let key = assignment.repositoryIds.count > 1 ? "Repositories: %@"
            : assignment.isCurrent ? "Repository: %@" : "Last observed repository: %@"
        return String(format: L(key), names.joined(separator: ", "))
    }

    static func meshSummary(_ snapshot: ProjectMeshSnapshot) -> String {
        let ids = ProjectTaskRepositoryGroups.confirmedRepositories(snapshot).sorted()
        if ids.isEmpty { return L("Workspace without confirmed Git") }
        let leaves = ids.map { ProjectOtherSide.displayName(of: $0, in: snapshot) }
        let names = zip(ids, leaves).map { id, name in
            leaves.filter { $0 == name }.count > 1 && !id.hasPrefix("local:") ? id : name
        }
        return String(format: L("Repositories: %@"), names.joined(separator: ", "))
    }
}
