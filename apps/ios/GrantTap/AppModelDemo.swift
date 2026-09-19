import Foundation

@MainActor
extension AppModel {
    /// Deterministic, side-effect-free sample state available in App Store builds.
    func startDemo() {
        relay?.disconnect()
        relay = nil
        demoMode = true
        connected = false

        let now = Date().timeIntervalSince1970 * 1000
        let sessionId = AppModelDemoFixtures.codexSessionId
        pending = AppModelDemoFixtures.approvals(at: now)
        questions = AppModelDemoFixtures.questions(at: now)
        #if DEBUG
        // Deterministic clean task-list capture. This is never compiled into
        // release builds and keeps the normal interactive demo unchanged.
        if ProcessInfo.processInfo.environment["GRANTTAP_CAPTURE_TASKS"] == "1" {
            pending = []
            questions = []
        }
        #endif
        sessions = AppModelDemoFixtures.sessions(at: now)
        sessionHistory = AppModelDemoFixtures.history(at: now)
        activities = AppModelDemoFixtures.activities(at: now)
        let mesh = AppModelDemoMeshFixtures.snapshot(at: now)
        meshSnapshots = [mesh.projectId: mesh]
        projectGovernance = [mesh.projectId: AppModelDemoMeshFixtures.governance(at: now)]
        pendingProjectPolicyRevisions = [:]
        projectPolicyErrors = [:]
        pendingMeshEvents = []
        activities[AppModelDemoMeshFixtures.previousClaudeSessionId] =
            AppModelDemoMeshFixtures.previousActivity(at: now)
        #if DEBUG
        if ProcessInfo.processInfo.environment["GRANTTAP_CHAT_SCREENSHOT"] != nil
            || ProcessInfo.processInfo.environment["GRANTTAP_IMAGE_PREVIEW_SCREENSHOT"] != nil {
            let capture = AppModelDemoFixtures.chatCapture(at: now)
            activities[AppModelDemoFixtures.codexSessionId] = capture.activity
            deliveries = [capture.delivery]
            pending = []
            questions = []
        }
        #endif
        agentIntegrations = [
            AgentIntegrationInfo(agent: "codex", installed: true, hookConfigured: true),
            AgentIntegrationInfo(agent: "claude", installed: true, hookConfigured: true),
        ]
        tokensRecent = 18_420
        tokenWindowHours = 12
        machineName = L("Review Mac")
        gatingEnabled = true
        excludedSessions = []
        autoAcceptDefault = "except_push"
        autoAcceptBySession = [:]
        autoAcceptByProject = [:]
        autoAcceptPaused = false
        archivedProjectComputers = [:]
        removedProjectComputers = [:]
        log = [L("Demo mode: no command will be executed.")]
        #if DEBUG
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let gtKeys = ProcessInfo.processInfo.environment.keys.filter { $0.contains("GRANTTAP") }.sorted()
        try? "keys=\(gtKeys) open=\(ProcessInfo.processInfo.environment["GRANTTAP_OPEN_SESSION"] ?? "nil")\n"
            .write(to: docs.appendingPathComponent("granttap-open-debug.txt"),
                   atomically: true, encoding: .utf8)
        if ProcessInfo.processInfo.environment["GRANTTAP_OPEN_SESSION"] != nil {
            sessionToOpen = sessionId
        }
        #endif
        pushToWatch()
    }
}

@MainActor
extension AppModel {
    /// Clears any developer-demo residue. This stays available in Release because
    /// shared connection recovery and Settings code must compile without demo data.
    func stopDemo() {
        pending = []
        questions = []
        log = []
        compactingSessions = []
        compactResults = [:]
        tokensRecent = 0
        machineName = ""
        excludedSessions = []
        autoAcceptDefault = "except_push"
        autoAcceptBySession = [:]
        autoAcceptByProject = [:]
        autoAcceptPaused = false
        archivedProjectComputers = [:]
        removedProjectComputers = [:]
        activitySubscribers = [:]
        // Clears demo rows + SQLite so they cannot reappear after Pair.
        purgeDemoCatalogResidue(reason: "stop-demo")
        sessions = []
        sessionHistory = []
        activities = [:]
        meshSnapshots = [:]
        projectGovernance = [:]
        pendingProjectPolicyRevisions = [:]
        projectPolicyErrors = [:]
        pendingMeshEvents = []
        deliveries.removeAll { $0.id == "demo-photo-delivery" }
        pushToWatch()
    }
}
