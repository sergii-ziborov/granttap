import SwiftUI

@MainActor
struct CapabilityUsageHistoryView: View {
    let kind: CapabilityUsageKind
    let name: String
    let agent: String?
    let modelName: String?
    let outcome: CapabilityOutcome?
    var server: McpServerInfo? = nil
    /// Only these chats, when the list is opened from a task or a Project.
    /// The global Usage tab passes nothing and sees every call.
    var sessionIds: Set<String>? = nil
    @ObservedObject private var model: AppModel
    @ObservedObject private var usage: CapabilityUsageStore

    init(
        kind: CapabilityUsageKind, name: String, agent: String?, modelName: String?,
        server: McpServerInfo? = nil, outcome: CapabilityOutcome? = nil,
        sessionIds: Set<String>? = nil,
        appModel: AppModel? = nil,
        usage: CapabilityUsageStore? = nil
    ) {
        self.kind = kind
        self.name = name
        self.agent = agent
        self.modelName = modelName
        self.server = server
        self.outcome = outcome
        self.sessionIds = sessionIds
        model = appModel ?? .shared
        self.usage = usage ?? .shared
    }

    private var events: [CapabilityUsageEvent] {
        usage.events.filter(matches)
    }

    func matches(_ event: CapabilityUsageEvent) -> Bool {
        guard event.kind == kind, event.name == name else { return false }
        if let sessionIds, event.sessionId.map(sessionIds.contains) != true { return false }
        if let agent,
           AgentIdentity.normalize(event.agent ?? "") != AgentIdentity.normalize(agent) {
            return false
        }
        if let modelName,
           event.model?.lowercased() != modelName.lowercased() { return false }
        return outcome == nil || event.effectiveOutcome == outcome
    }

    /// The Project these calls belong to, when they all belong to one; a rule
    /// is only offered when there is exactly one policy it could go into.
    var governedProjectId: String? {
        let ids = Set(events.compactMap(\.sessionId))
        guard !ids.isEmpty else { return nil }
        return ProjectGovernanceQuickRule.projectId(for: ids, in: model)
    }

    @State private var toast: String?

    private var title: String {
        kind == .mcp
            ? (server?.displayTitle ?? MCPIdentity(name: name).displayName)
            : name
    }

    var body: some View {
        List {
            Section {
                if kind == .mcp {
                    HStack(spacing: 11) {
                        MCPBadge(name: name, size: 38, server: server)
                        Text(title).font(.headline)
                    }
                } else {
                    Label(title, systemImage: kind == .cli ? "terminal" : "wand.and.stars")
                        .font(.headline)
                }
                Text([agent.map(AgentIdentity.displayName), modelName]
                    .compactMap { $0 }
                    .joined(separator: " · "))
                    .font(.caption)
                    .foregroundStyle(Theme.muted)
            }

            Section {
                if events.isEmpty {
                    Text(outcome == .error
                         ? L("No failed calls retained on this iPhone.")
                         : L("No calls recorded yet."))
                        .foregroundStyle(Theme.muted)
                } else {
                    ForEach(events) { event in
                        if let target = linkedTarget(for: event) {
                            let session = linkedSession(for: target)
                            NavigationLink {
                                CapabilityChatDestination(
                                    target: target,
                                    createdAt: event.createdAt,
                                    focusEntryId: CapabilityTranscriptLink.entryId(
                                        sourceId: event.sourceId, roomId: target.roomId
                                    )
                                )
                                .environmentObject(model)
                            } label: {
                                eventRow(
                                    event,
                                    linkedChatTitle: session?.displayTitle ?? L("Load chat history")
                                )
                            }
                        } else {
                            eventRow(event, linkedChatTitle: nil)
                        }
                    }
                }
            } header: {
                Text(L("Call history"))
            } footer: {
                Text(L("Saved appears only when the Mac helper could compare the result to a local file size. Latency is tool_use → tool_result wall time."))
            }
        }
        .navigationTitle(outcome == .error ? L("Failed calls") : L("History"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                if let projectId = governedProjectId {
                    ProjectGovernanceQuickMenu(
                        kind: kind, name: name, projectId: projectId, model: model, toast: $toast
                    )
                }
            }
        }
        .transientToast($toast)
    }

    func linkedTarget(for event: CapabilityUsageEvent) -> CapabilityChatTarget? {
        CapabilityChatLink.target(for: event, model: model)
    }

    func linkedSession(for target: CapabilityChatTarget) -> SessionInfo? {
        let resolved = model.resolvedSessionId(target.sessionId)
        return model.sessions.first { $0.sessionId == resolved }
            ?? model.sessionHistory.first { $0.sessionId == resolved }
            ?? model.archivedSessions[resolved]
            ?? model.sessions.first { $0.sessionId == target.sessionId }
            ?? model.sessionHistory.first { $0.sessionId == target.sessionId }
            ?? model.archivedSessions[target.sessionId]
    }

    private func eventRow(_ event: CapabilityUsageEvent,
                          linkedChatTitle: String?) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text(shortTool(event.toolName) ?? event.name)
                    .font(.system(size: 14, weight: .semibold))
                    .lineLimit(1)
                Spacer()
                Text(date(event.createdAt))
                    .font(.caption)
                    .foregroundStyle(Theme.muted)
            }
            if kind == .cli, let preview = event.commandPreview {
                Text(preview)
                    .font(Theme.mono(11))
                    .foregroundStyle(Theme.ink)
                    .lineLimit(2)
            }
            if event.effectiveOutcome == .error {
                Label(
                    [L("Failed"), event.errorClass].compactMap { $0 }.joined(separator: " · "),
                    systemImage: "exclamationmark.triangle.fill"
                )
                .font(.caption.weight(.semibold))
                .foregroundStyle(Theme.riskHigh)
            }
            HStack(spacing: 10) {
                if let tokens = event.estimatedContextTokens, tokens > 0 {
                    Label("≈ \(Format.tokens(tokens)) context", systemImage: "number")
                }
                if let saved = event.estimatedTokensSaved, saved > 0 {
                    Label(Format.tokens(saved), systemImage: "arrow.down.circle")
                        .foregroundStyle(Theme.ok)
                }
                if let ms = event.durationMs {
                    Label(Format.latencyMs(ms), systemImage: "timer")
                }
            }
            .font(.caption)
            .foregroundStyle(Theme.muted)
            if let resource = event.resource {
                HStack(spacing: 10) {
                    if let peak = resource.effectivePeakRssBytes {
                        Label("\(CapabilityResourceFormat.bytes(peak)) peak", systemImage: "memorychip")
                    }
                    if let cpu = resource.effectiveCpuTimeMs {
                        Label("\(cpu) ms CPU", systemImage: "cpu")
                    }
                }
                .font(.caption)
                .foregroundStyle(Theme.muted)
                Text(attribution(resource.attribution))
                    .font(.caption2)
                    .foregroundStyle(Theme.muted)
            }
            if let linkedChatTitle {
                Label("Open chat · \(linkedChatTitle)", systemImage: "bubble.left.and.bubble.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Theme.codex)
                    .lineLimit(1)
            }
        }
        .padding(.vertical, 2)
    }

    func attribution(_ value: CapabilityResourceAttribution) -> String {
        switch value {
        case .measured: return L("Attribution: measured")
        case .attributed where kind == .skill:
            return L("Attribution: observed during skill execution")
        case .attributed: return L("Attribution: attributed")
        case .estimated: return L("Attribution: estimated")
        case .unknown: return L("Attribution: unknown")
        }
    }

    private func shortTool(_ toolName: String?) -> String? {
        guard let toolName, !toolName.isEmpty else { return nil }
        if let range = toolName.range(of: "__", options: .backwards) {
            return String(toolName[range.upperBound...])
        }
        return toolName
    }

    private func date(_ milliseconds: Double) -> String {
        Date(timeIntervalSince1970: milliseconds / 1000)
            .formatted(
                .dateTime
                    .locale(Locale(identifier: AppLocale.speechIdentifier))
                    .month(.abbreviated)
                    .day()
                    .hour()
                    .minute()
                    .second()
            )
    }
}

/// Usage can outlive the bounded 40-row history catalog. Pin the authenticated
/// room first, then subscribe with a lightweight placeholder; the monitor
/// reserves a history slot for that subscription and hydrates full metadata.
