#if DEBUG
import Foundation

enum TurnModelPickerFixture {
    @MainActor static func apply(to model: AppModel, at now: Double) {
        guard ProcessInfo.processInfo.environment["GRANTTAP_DEMO"] == "1",
              ProcessInfo.processInfo.environment["GRANTTAP_TEST_MODELS"] == "1",
              var snapshot = model.meshSnapshots[AppModelDemoMeshFixtures.projectId] else { return }
        let metadata = [
            ("gpt-6-astra", "GPT-6 Astra", "Frontier intelligence for the most demanding work."),
            ("gpt-6-sol", "GPT-6 Sol", "Workhorse model for coding and everyday work."),
            ("gpt-6-luna", "GPT-6 Luna", "Fast and affordable model for easier tasks."),
        ]
        snapshot.modelCatalog = [ProjectEndpointModelCatalog(endpointId: "Workstation", observedAt: now,
            models: metadata.enumerated().map { index, item in
                ProjectAdvertisedModel(modelId: item.0, provider: "codex", endpointId: "Workstation",
                    source: "advertised", label: item.1, description: item.2, priority: index, observedAt: now)
            })]
        model.meshSnapshots[snapshot.projectId] = snapshot
        if let index = model.sessions.firstIndex(where: { $0.sessionId == AppModelDemoFixtures.codexSessionId }) {
            model.sessions[index].model = "gpt-6-sol"
            model.turnOverrides.setChatOverrides(.unchanged, for: model.sessions[index].sessionId)
            model.turnOverrides.setAgentDefaults(.unchanged, for: "codex")
        }
    }
}
#endif
