import Foundation

struct TurnModelOption: Equatable, Identifiable {
    let model: TurnModel
    let label: String
    let detail: String
    var id: String { model.id }
}

struct TurnModelCatalog: Equatable {
    let options: [TurnModelOption]
    var checkedAt: Double? = nil
    var stale = false

    static func resolve(agent: String, endpointId: String?, catalogs: [ProjectEndpointModelCatalog],
                        now: Double = Date().timeIntervalSince1970 * 1_000) -> Self {
        let provider = AgentIdentity.normalize(agent)
        let catalog = catalogs.filter { $0.endpointId == endpointId }
            .max { $0.observedAt < $1.observedAt }
        let native = (catalog?.models ?? []).filter {
            $0.endpointId == endpointId && $0.provider == provider && $0.source == "advertised"
                && catalog?.stale != true && $0.observedAt > 0
                && now - $0.observedAt <= 24 * 60 * 60_000 && $0.observedAt - now <= 5 * 60_000
        }.sorted { ($0.priority ?? 10_000) < ($1.priority ?? 10_000) }
        var seen = Set<String>()
        let rows = native.compactMap { row -> TurnModelOption? in
            guard let model = TurnModel(rawValue: row.modelId), model.accepted(by: provider),
                  seen.insert(row.modelId).inserted else { return nil }
            return TurnModelOption(model: model, label: row.label ?? model.label,
                detail: row.description.map(L) ?? L("Available in the provider's model catalog."))
        }
        let aliases = TurnModel.supported(by: provider).filter { !seen.contains($0.id) }.map {
            TurnModelOption(model: $0, label: $0.label, detail: aliasDetail($0))
        }
        return Self(options: rows + aliases, checkedAt: native.map(\.observedAt).max(),
                    stale: provider == "codex" && native.isEmpty)
    }

    private static func aliasDetail(_ model: TurnModel) -> String {
        switch model {
        case .opus: return L("Latest Opus alias · complex reasoning tasks.")
        case .sonnet: return L("Latest Sonnet alias · everyday coding tasks.")
        case .haiku: return L("Latest Haiku alias · fast, efficient simple tasks.")
        case .fable: return L("Fable alias · hardest and longest-running tasks. May require usage credits.")
        default: return L("The installed provider resolves this alias.")
        }
    }
}

struct TurnModelChange: Identifiable {
    let choice: TurnModel?
    var id: String { choice?.id ?? "current" }

    static func needsConfirmation(choice: TurnModel?, selection: TurnModel?, current: String?,
                                  fallback: String?, hasConversation: Bool) -> Bool {
        guard hasConversation else { return false }
        let before = selection?.rawValue ?? fallback ?? current
        let after = choice?.rawValue ?? fallback ?? current
        return before != after
    }
}
