import Foundation

/// What a GrantTap auto-accept level does, in the same classes the Mac hook uses.
enum AutoAcceptActionClass: String, CaseIterable, Identifiable {
    case read, edit, bash, mcp, gitPush = "git_push", gitForce = "git_force"
    case destructive, networkWrite = "network_write"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .read: return L("Reads")
        case .edit: return L("Edits")
        case .bash: return L("Shell")
        case .mcp: return L("MCP")
        case .gitPush: return L("Push")
        case .gitForce: return L("Force push")
        case .destructive: return L("Destructive")
        case .networkWrite: return L("Network write")
        }
    }
}

enum AutoAcceptPresentation {
    static func resolved(
        paused: Bool,
        session: String?,
        project: String?,
        machine: String
    ) -> AutoAcceptLevel {
        if paused { return .ask }
        if let session { return AutoAcceptLevel.parse(session) }
        if let project { return AutoAcceptLevel.parse(project) }
        return AutoAcceptLevel.parse(machine)
    }

    static func allows(_ level: AutoAcceptLevel, _ cls: AutoAcceptActionClass) -> Bool {
        if level == .ask { return false }
        if level == .full { return true }
        if level == .safe { return cls == .read }
        if level == .exceptPush {
            return ![.gitPush, .gitForce, .destructive, .networkWrite].contains(cls)
        }
        return ![.gitForce, .destructive, .networkWrite].contains(cls)
    }

    static func summary(
        paused: Bool,
        project: String?,
        machine: String
    ) -> String {
        if paused { return L("Paused") }
        if let project {
            return AutoAcceptLevel.parse(project).title
        }
        return "\(AutoAcceptLevel.parse(machine).title) · \(L("Inherited"))"
    }

    static func verdict(_ level: AutoAcceptLevel, _ cls: AutoAcceptActionClass) -> String {
        allows(level, cls) ? L("Auto") : L("Ask")
    }
}
