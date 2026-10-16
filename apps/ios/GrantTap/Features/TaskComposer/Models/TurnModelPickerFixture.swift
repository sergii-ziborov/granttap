#if DEBUG
import Foundation

enum TurnModelPickerFixture {
    @MainActor static func apply(to model: AppModel, at now: Double) {
        guard ProcessInfo.processInfo.environment["GRANTTAP_DEMO"] == "1",
              var snapshot = model.meshSnapshots[AppModelDemoMeshFixtures.projectId] else { return }
        let metadata = [
            ("gpt-6-astra", "GPT-6 Astra", "Frontier intelligence for the most demanding work."),
            ("gpt-6-sol", "GPT-6 Sol", "Workhorse model for coding and everyday work."),
            ("gpt-6-luna", "GPT-6 Luna", "Fast and affordable model for easier tasks."),
        ]
        snapshot.modelCatalog = [ProjectEndpointModelCatalog(endpointId: "Workstation", observedAt: now,
            models: metadata.enumerated().map { index, item in
                ProjectAdvertisedModel(modelId: item.0, provider: "codex", endpointId: "Workstation",
                    source: "advertised", label: item.1, description: item.2, priority: index, supportedEfforts: index == 2
                        ? ["low", "medium", "high", "max"] : ["low", "medium", "high", "xhigh", "max", "ultra"], observedAt: now)
            }, accountUsage: [ProviderAccountUsage(provider: "codex", limitId: "codex", observedAt: now,
                windows: [ProviderUsageWindow(id: "primary", usedPercent: 23, windowMinutes: 300,
                    resetsAt: now + 3_600_000)])])]
        model.meshSnapshots[snapshot.projectId] = snapshot
        if ProcessInfo.processInfo.environment["GRANTTAP_TEST_TRANSFER_CONTROLS"] == "1" {
            let room = "model-controls-demo"
            model.connectionRegistry = ConnectionRegistryLogic.upsert(.empty, pairing: Pairing(
                relayUrl: "ws://127.0.0.1:1", room: room, role: "phone", deviceName: "Demo Mac",
                senderId: "demo", myPublicKey: "demo", mySecretKey: "demo", peerPublicKey: "demo"))
            model.rememberSessionSourceRoom(room, sessionId: AppModelDemoFixtures.codexSessionId)
            model.meshComputerRoomByEndpointId["Workstation"] = room
        }
        if let index = model.sessions.firstIndex(where: { $0.sessionId == AppModelDemoFixtures.codexSessionId }) {
            model.sessions[index].model = "gpt-6-sol"
            if let effort = ProcessInfo.processInfo.environment["GRANTTAP_TEST_CURRENT_EFFORT"] {
                model.sessions[index].effort = effort
            }
            if ProcessInfo.processInfo.environment["GRANTTAP_TEST_MODELS"] == "1" {
                model.turnOverrides.setChatOverrides(.unchanged, for: model.sessions[index].sessionId)
                model.turnOverrides.setAgentDefaults(.unchanged, for: "codex")
            }
        }
    }
}
#endif
