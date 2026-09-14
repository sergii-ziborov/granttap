import Foundation

enum TaskComposerRouteColumn: String, CaseIterable {
    case provider
    case computer
    case workspace
}

struct TaskComposerRouteLabel: Equatable {
    let compact: String
    let accessibility: String

    init(_ value: String, maximumCharacters: Int = 22) {
        let clean = value.trimmingCharacters(in: .whitespacesAndNewlines)
        accessibility = clean
        guard clean.count > maximumCharacters else {
            compact = clean
            return
        }
        compact = String(clean.prefix(maximumCharacters)) + "…"
    }
}

enum ComputerAvailabilityTone: Equatable {
    case live
    case transitional
    case offline

    init(phase: ConnectionPhase) {
        switch phase {
        case .live:
            self = .live
        case .demo, .macOffline, .needRepair:
            self = .transitional
        case .notLinked, .phoneOffline:
            self = .offline
        }
    }
}

enum TaskComposerRoutePresentation {
    static func defaultProvider(
        saved: String?, sessions: [SessionInfo], enabledProviders: Set<String>
    ) -> String {
        if let saved {
            let normalized = AgentIdentity.normalize(saved)
            if enabledProviders.contains(normalized) { return normalized }
        }
        if let recent = sessions
            .sorted(by: { $0.lastActivityAt > $1.lastActivityAt })
            .map({ AgentIdentity.normalize($0.agent) })
            .first(where: enabledProviders.contains) {
            return recent
        }
        return AgentIdentity.composeIds.first(where: enabledProviders.contains)
            ?? AgentIdentity.composeIds[0]
    }

    static func computerName(pairingLabel: String, publishedMachineName: String) -> String {
        let machine = publishedMachineName.trimmingCharacters(in: .whitespacesAndNewlines)
        return machine.isEmpty ? pairingLabel : machine
    }

    static func providerMetadata(phase: ConnectionPhase, mcpCount: Int) -> String {
        let availability = phase == .live ? L("Online") : L("Offline")
        let capabilities = mcpCount == 0 ? L("No MCP") : "\(mcpCount) MCP"
        return "\(availability) · \(capabilities)"
    }
}
