import SwiftUI

extension ContentView {
    func handleAppear() {
        #if DEBUG
        if ProcessInfo.processInfo.environment["GRANTTAP_E2E_RESET_ARCHIVE"] == "1" {
            model.archivedSessionIds = []
            model.archivedSessions = [:]
            model.persistArchivedSessions()
            ArchivedSessionPersistence.save([:])
        }
        if ProcessInfo.processInfo.environment["GRANTTAP_DEMO"] == "1" { model.startDemo() }
        switch ProcessInfo.processInfo.environment["GRANTTAP_CAPTURE_TAB"] {
        case "tasks": selectedTab = .tasks
        case "usage": selectedTab = .usage
        default: break
        }
        if ProcessInfo.processInfo.environment["GRANTTAP_OPEN_SESSION"] != nil {
            Task { @MainActor in
                for _ in 0..<40 {
                    if !security.launching { break }
                    try? await Task.sleep(nanoseconds: 50_000_000)
                }
                try? await Task.sleep(nanoseconds: 200_000_000)
                if openedSession == nil, let first = model.sessions.first {
                    openedSession = OpenSession(id: first.sessionId)
                }
                let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
                let line = "opened=\(openedSession?.id ?? "nil") sessions=\(model.sessions.count) launching=\(security.launching) demo=\(model.demoMode)\n"
                try? line.write(to: docs.appendingPathComponent("granttap-open-debug.txt"),
                                atomically: true, encoding: .utf8)
            }
        }
        showSettings = ProcessInfo.processInfo.environment["GRANTTAP_SETTINGS"] != nil
        showChatHistory = ProcessInfo.processInfo.environment["GRANTTAP_CHAT_HISTORY"] != nil
        if ProcessInfo.processInfo.environment["GRANTTAP_USAGE_SCREENSHOT"] != nil {
            seedUsageScreenshot()
            showCapabilityUsage = true
        }
        #endif
        security.sceneChanged(.active)
    }

    func handleScenePhase(_ phase: ScenePhase) {
        if phase == .background { LoadHistoryPersistence.flush() }
        if phase != .active && security.enabled { putAway() }
        if phase == .active {
            if model.connected { model.retryQueuedDeliveries() }
            if model.needsForegroundCatalogRecovery {
                model.recoverCatalogAfterForeground()
            } else if model.connected, model.sessions.isEmpty {
                Task { await model.refreshSessions() }
            }
        }
        security.sceneChanged(phase)
        // Back where the screen went dark — unless the gate has just come
        // down, in which case the unlock brings it back.
        if phase == .active, !security.locked { bringBack() }
    }

    func handleLockChange(_ locked: Bool) {
        if locked {
            putAway()
        } else {
            bringBack()
        }
    }

    /// Remember the chat and sheet in front, then hide them: a sheet is
    /// presented above the lock screen and would show through it.
    private func putAway() {
        if lockedAway == nil {
            lockedAway = LockedAway(
                session: openedSession, settings: showSettings, pairing: showPairing,
                usage: showCapabilityUsage, history: showChatHistory
            )
        }
        openedSession = nil
        showSettings = false
        showPairing = false
        showCapabilityUsage = false
        showChatHistory = false
    }

    private func bringBack() {
        guard let away = lockedAway else { return }
        lockedAway = nil
        openedSession = away.session
        showSettings = away.settings
        showPairing = away.pairing
        showCapabilityUsage = away.usage
        showChatHistory = away.history
    }

    private func seedUsageScreenshot() {
        let now = Date().timeIntervalSince1970 * 1000
        for index in 0..<10 {
            CapabilityUsageStore.shared.record(
                .mcp, name: "github", sessionId: "granttap-review-demo",
                sourceId: "screenshot:github:\(index)", createdAt: now - Double(index) * 86_000,
                toolName: "mcp__github__status", estimatedContextTokens: 260 + index * 17
            )
        }
        for index in 0..<4 {
            CapabilityUsageStore.shared.record(
                .mcp, name: "cloudflare", sessionId: "granttap-review-demo",
                sourceId: "screenshot:cloudflare:\(index)", createdAt: now - Double(index) * 120_000,
                toolName: "mcp__cloudflare__query", estimatedContextTokens: 190 + index * 23
            )
        }
        CapabilityUsageStore.shared.record(
            .mcp, name: "figma", sessionId: "granttap-review-demo",
            sourceId: "screenshot:figma", createdAt: now - 190_000,
            toolName: "mcp__figma__get_design_context", estimatedContextTokens: 740
        )
    }
}

/// The chat and the sheet that were open when the app was put away.
struct LockedAway {
    var session: OpenSession?
    var settings: Bool
    var pairing: Bool
    var usage: Bool
    var history: Bool
}
