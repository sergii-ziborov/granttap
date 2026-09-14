import Foundation

struct AgentMeshPreferences: Codable, Equatable {
    var providerSettings: [String: Bool]
    var meshEnabled: Bool

    static let defaults = AgentMeshPreferences(
        providerSettings: Dictionary(uniqueKeysWithValues: AgentIdentity.knownIds.map { ($0, true) }),
        meshEnabled: true
    )

    var enabledProviders: Set<String> {
        Set(AgentIdentity.knownIds.filter { isProviderEnabled($0) })
    }

    func isProviderEnabled(_ provider: String) -> Bool {
        providerSettings[AgentIdentity.normalize(provider)] ?? true
    }
}

enum AgentMeshPreferencesStore {
    static let key = "granttap.agents-mesh.preferences.v1"

    static func load(defaults: UserDefaults = .standard) -> AgentMeshPreferences {
        guard let data = defaults.data(forKey: key),
              var value = try? JSONDecoder().decode(AgentMeshPreferences.self, from: data)
        else { return .defaults }
        for provider in AgentIdentity.knownIds where value.providerSettings[provider] == nil {
            value.providerSettings[provider] = true
        }
        value.providerSettings = value.providerSettings.filter {
            AgentIdentity.knownIds.contains($0.key)
        }
        return value
    }

    static func save(_ value: AgentMeshPreferences, defaults: UserDefaults = .standard) {
        guard let data = try? JSONEncoder().encode(value) else { return }
        defaults.set(data, forKey: key)
    }
}
