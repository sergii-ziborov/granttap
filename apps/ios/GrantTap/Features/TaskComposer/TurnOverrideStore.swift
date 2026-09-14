import Foundation

/// Where "answer with" choices live.
///
/// A single global pair was wrong twice over: models differ per provider, so
/// one shared value is meaningless for the others, and a per-chat choice held
/// only in view state vanished the moment the chat was closed.
///
/// So: defaults are kept **per agent**, overrides are kept **per chat**, and
/// both survive a relaunch.
struct TurnOverrideStore {
    private let defaults: UserDefaults
    private static let agentModels = "granttap.turn-model-by-agent"
    private static let agentModes = "granttap.turn-permission-by-agent"
    private static let chatModels = "granttap.turn-model-by-chat"
    private static let chatModes = "granttap.turn-permission-by-chat"
    private static let agentEfforts = "granttap.turn-effort-by-agent"
    private static let chatEfforts = "granttap.turn-effort-by-chat"
    /// A phone accumulates chats forever; the stored overrides must not.
    private static let maxChats = 200

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    private func map(_ key: String) -> [String: String] {
        defaults.dictionary(forKey: key) as? [String: String] ?? [:]
    }

    private func write(_ value: String?, forKey id: String, in key: String) {
        var current = map(key)
        if let value {
            current[id] = value
            // Oldest-first eviction is impossible without timestamps, so bound
            // by dropping arbitrary entries only once the map is clearly stale.
            if current.count > Self.maxChats, let victim = current.keys.first(where: { $0 != id }) {
                current.removeValue(forKey: victim)
            }
        } else {
            current.removeValue(forKey: id)
        }
        defaults.set(current, forKey: key)
    }

    // MARK: per-agent defaults

    func agentDefaults(for agent: String) -> TurnOverrides {
        let key = AgentIdentity.normalize(agent)
        return TurnOverrides(
            model: map(Self.agentModels)[key].flatMap(TurnModel.init(rawValue:)),
            permissionMode: map(Self.agentModes)[key].flatMap(TurnPermissionMode.init(rawValue:)),
            effort: map(Self.agentEfforts)[key].flatMap(TurnEffort.init(rawValue:))
        )
    }

    func setAgentDefaults(_ overrides: TurnOverrides, for agent: String) {
        let key = AgentIdentity.normalize(agent)
        write(overrides.model?.rawValue, forKey: key, in: Self.agentModels)
        write(overrides.permissionMode?.rawValue, forKey: key, in: Self.agentModes)
        write(overrides.effort?.rawValue, forKey: key, in: Self.agentEfforts)
    }

    // MARK: per-chat overrides

    func chatOverrides(_ sessionId: String) -> TurnOverrides {
        TurnOverrides(
            model: map(Self.chatModels)[sessionId].flatMap(TurnModel.init(rawValue:)),
            permissionMode: map(Self.chatModes)[sessionId].flatMap(TurnPermissionMode.init(rawValue:)),
            effort: map(Self.chatEfforts)[sessionId].flatMap(TurnEffort.init(rawValue:))
        )
    }

    func setChatOverrides(_ overrides: TurnOverrides, for sessionId: String) {
        write(overrides.model?.rawValue, forKey: sessionId, in: Self.chatModels)
        write(overrides.permissionMode?.rawValue, forKey: sessionId, in: Self.chatModes)
        write(overrides.effort?.rawValue, forKey: sessionId, in: Self.chatEfforts)
    }

    /// What this chat should actually answer with: its own choice first, then
    /// the default for its provider.
    func resolved(sessionId: String, agent: String) -> TurnOverrides {
        TurnOverrides.resolve(
            chat: chatOverrides(sessionId),
            fallback: agentDefaults(for: agent)
        )
    }
}
