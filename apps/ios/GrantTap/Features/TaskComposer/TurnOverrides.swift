import Foundation

/// What a chat should answer with, when the user wants something other than the
/// chat's own defaults.
///
/// Both are deliberately optional and default to "unchanged": a turn that picks
/// nothing must reach the computer exactly as it always did. The values become
/// command-line arguments, so the list of what may be chosen lives here rather
/// than being assembled from free text at the call site.
enum TurnModel: String, CaseIterable, Identifiable {
    case opus, sonnet, haiku, fable
    case gpt56Sol = "gpt-5.6-sol"
    case gpt56Terra = "gpt-5.6-terra"
    case gpt56Luna = "gpt-5.6-luna"
    case gpt55 = "gpt-5.5"

    var id: String { rawValue }

    var label: String {
        switch self {
        case .opus: return "Opus"
        case .sonnet: return "Sonnet"
        case .haiku: return "Haiku"
        case .fable: return "Fable"
        case .gpt56Sol: return "GPT-5.6 Sol"
        case .gpt56Terra: return "GPT-5.6 Terra"
        case .gpt56Luna: return "GPT-5.6 Luna"
        case .gpt55: return "GPT-5.5"
        }
    }

    /// Providers that accept a model alias for a headless turn.
    static func supported(by agent: String) -> [TurnModel] {
        switch AgentIdentity.normalize(agent) {
        case "claude": return [.opus, .sonnet, .haiku, .fable]
        case "codex": return [.gpt56Sol, .gpt56Terra, .gpt56Luna, .gpt55]
        default: return []
        }
    }
}

enum TurnPermissionMode: String, CaseIterable, Identifiable {
    case `default`, acceptEdits, bypassPermissions, plan

    var id: String { rawValue }

    var label: String {
        switch self {
        case .default: return L("Ask each time")
        case .acceptEdits: return L("Accept edits")
        case .bypassPermissions: return L("Bypass permissions")
        case .plan: return L("Plan only")
        }
    }

    /// Spelled out because the strongest option removes a safety step and the
    /// user should read that before choosing it, not discover it afterwards.
    var detail: String {
        switch self {
        case .default: return L("The agent asks before each tool it runs.")
        case .acceptEdits: return L("File edits go through; other tools still ask.")
        case .bypassPermissions: return L("The agent runs tools without asking. GrantTap's own blocks still apply.")
        case .plan: return L("The agent plans without running anything.")
        }
    }

    /// What the CLI is actually given, or nil when the case means "unchanged".
    ///
    /// The CLI defines acceptEdits, auto, bypassPermissions, manual, dontAsk
    /// and plan. It has no "default", so that case travels as nothing rather
    /// than as a word the agent would reject.
    var wireValue: String? { self == .default ? nil : rawValue }

    static func supported(by agent: String) -> [TurnPermissionMode] {
        agent.lowercased() == "claude" ? allCases : []
    }
}

/// How hard the model should work on a turn.
enum TurnEffort: String, CaseIterable, Identifiable {
    case low, medium, high, xhigh, max

    var id: String { rawValue }

    var label: String {
        switch self {
        case .low: return L("Low")
        case .medium: return L("Medium")
        case .high: return L("High")
        case .xhigh: return L("Very high")
        case .max: return L("Maximum")
        }
    }

    /// Only Claude is driven with an effort flag here. Codex is not, so an
    /// effort chosen for it must not travel as a value its CLI would reject.
    static func supported(by agent: String) -> [TurnEffort] {
        AgentIdentity.normalize(agent) == "claude" ? allCases : []
    }
}

/// The per-chat choices, resolved against a global default.
struct TurnOverrides: Equatable {
    var model: TurnModel?
    var permissionMode: TurnPermissionMode?
    var effort: TurnEffort?

    static let unchanged = TurnOverrides()

    /// A chat's own choice wins; otherwise the global default applies. Neither
    /// being set means the turn carries nothing at all.
    static func resolve(chat: TurnOverrides, fallback: TurnOverrides) -> TurnOverrides {
        TurnOverrides(
            model: chat.model ?? fallback.model,
            permissionMode: chat.permissionMode ?? fallback.permissionMode,
            effort: chat.effort ?? fallback.effort
        )
    }

    /// Only send what the provider can actually act on.
    ///
    /// `advertised` is the host catalog. Passing it, even empty, means aliases
    /// are labels only and must not become a route id.
    func wire(for agent: String, advertised: [String]? = nil) -> (model: String?, permissionMode: String?, effort: String?) {
        let models = advertised ?? TurnModel.supported(by: agent).map(\.rawValue)
        let modes = TurnPermissionMode.supported(by: agent)
        let efforts = TurnEffort.supported(by: agent)
        return (
            model.flatMap { models.contains($0.rawValue) ? $0.rawValue : nil },
            permissionMode.flatMap { modes.contains($0) ? $0.wireValue : nil },
            effort.flatMap { efforts.contains($0) ? $0.rawValue : nil }
        )
    }
}
