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
        var mesh = AppModelDemoMeshFixtures.snapshot(at: now)
        #if DEBUG
        ChatMessageQueueFixture.apply(to: self, at: now)
        if ProcessInfo.processInfo.environment["GRANTTAP_TEST_GRAPH_LARGE"] == "1" {
            mesh.repositoryGraphs = [AppModelDemoMeshFixtures.largeArchitectureGraph()]
        } else if ProcessInfo.processInfo.environment["GRANTTAP_TEST_GRAPH"] == "1" {
            mesh.repositoryGraphs = [AppModelDemoMeshFixtures.architectureGraph()]
        }
        #endif
        meshSnapshots = [mesh.projectId: mesh]
        applyDemoMeshPresentationFixtures(mesh: &mesh, at: now)
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
        if ProcessInfo.processInfo.environment["GRANTTAP_TEST_ARTIFACT_IMAGES"] == "1" {
            activities[AppModelDemoFixtures.codexSessionId] = DemoMessageImages.activity(at: now)
            pending = []
            questions = []
        }
        if ProcessInfo.processInfo.environment["GRANTTAP_TEST_CHAT_SCROLL"] == "1" {
            activities[AppModelDemoFixtures.codexSessionId] = AppModelDemoFixtures.scrollActivity(at: now)
            pending = []
            questions = []
        }
        if DemoTranscriptHistory.enabled {
            activities[AppModelDemoFixtures.codexSessionId] = DemoTranscriptHistory.initial(at: now)
            pending = []
            questions = []
        }
        AttachmentPreviewFixture.applyScrollCapture(to: self, at: now)
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
        autoAcceptPaused = false
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
        autoAcceptPaused = false
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
