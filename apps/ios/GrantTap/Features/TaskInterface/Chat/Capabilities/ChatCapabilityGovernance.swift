import Foundation

/// Which Project capabilities decide a chat capability row.
///
/// Skills, MCP servers and the shell are Project policy, not per-task switches.
/// A shell row is governed by both `shell` and `script`: running a bash script
/// is not the same permission as typing a bash command, and the chat meets
/// whichever of the two is stricter.
enum ChatCapabilityGovernance {
    static func governing(_ kind: ChatCapabilityRow.Kind) -> [ProjectCapabilityKind] {
        switch kind {
        case .mcp: return [.mcp]
        case .skill: return [.skill]
        case .cli: return [.shell, .script]
        }
    }

    /// The effect this chat actually meets, or nil when the Project has not
    /// reported a policy for it.
    ///
    /// A capability governed by more than one kind reports the strictest, so a
    /// denied script is never presented as an allowed shell.
    static func effect(
        for kind: ChatCapabilityRow.Kind,
        in projection: ProjectGovernanceProjection?
    ) -> ProjectPolicyEffect? {
        guard let projection else { return nil }
        let defaults = ProjectGovernanceLogic.defaultEffects(projection.policy)
        return governing(kind)
            .compactMap { defaults[$0] }
            .max { $0.severity < $1.severity }
    }
}
