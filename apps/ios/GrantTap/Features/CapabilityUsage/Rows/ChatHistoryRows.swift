import SwiftUI

struct HistoryRow: View {
    let session: SessionInfo
    let archived: Bool
    let route: ChatComputerRoute?

    var body: some View {
        HStack(spacing: 10) {
            AgentGlyph(agent: session.agent, size: 30)
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 5) {
                    Text(session.displayTitle).font(.system(size: 14, weight: .semibold)).lineLimit(1)
                    if archived { Image(systemName: "archivebox.fill").font(.caption2).foregroundStyle(Theme.muted) }
                }
                HStack(spacing: 5) {
                    Text(Format.tokens(session.tokensSession))
                    Text(L("·"))
                    Text(session.historyTimestamp.formatted(date: .abbreviated,
                                                            time: .shortened))
                        .accessibilityLabel(session.historyTimestampLabel)
                    if let count = session.mcpServers?.count, count > 0 {
                        Text(L("·"))
                        Text("\(count) MCP")
                    }
                }
                .font(.caption)
                .foregroundStyle(Theme.muted)
                Text(TaskRoutePresentation.sessionMetadata(
                    agent: session.agent, model: session.model,
                    project: session.projectGroupTitle, route: route
                ))
                .font(.caption2)
                .foregroundStyle(route?.phase == .live ? Theme.muted : Theme.riskMed)
                .lineLimit(1)
            }
        }
        .padding(.vertical, 3)
    }
}

/// Compact history peek (tokens / MCP) — Chat history list opens SessionDetailSheet.
struct HistoricalChatDetail: View {
    @EnvironmentObject private var model: AppModel
    let session: SessionInfo
    @State private var retainedEntries: RetainedChatContent<ActivityEntry>?

    private var chatSessionId: String { model.resolvedSessionId(session.sessionId) }

    private var entries: [ActivityEntry] {
        model.activities[chatSessionId]?.entries
            ?? model.activities[session.sessionId]?.entries
            ?? []
    }

    private var visibleEntries: [ActivityEntry] {
        retainedEntries?.visible(
            current: entries, sessionId: session.sessionId,
            roomId: model.connectionRegistry.preferredId
        ) ?? entries
    }

    private func retainCurrentEntries() {
        guard !entries.isEmpty else { return }
        retainedEntries = RetainedChatContent(
            sessionId: session.sessionId, roomId: model.connectionRegistry.preferredId,
            items: entries
        )
    }

    private var activitySnapshotKnown: Bool {
        model.activities[chatSessionId] != nil
            || model.activities[session.sessionId] != nil
    }

    private var accent: Color { Theme.accent(for: session.agent) }

    /// What decides this capability, said once.
    ///
    /// Usage history reported a bare allowed/blocked tick that came from the
    /// chat's own flags. Once a Project governs the capability that tick is no
    /// longer the whole answer, and two different answers to one question is
    /// worse than one honest one.
    @ViewBuilder private func capabilityState(
        _ kind: ChatCapabilityRow.Kind, locallyAllowed: Bool
    ) -> some View {
        if let effect = ChatCapabilityGovernance.effect(
            for: kind, in: session.projectId.flatMap { model.projectGovernance[$0] }
        ) {
            Text(ProjectGovernancePresentation.effectLabel(effect))
                .font(.caption.weight(.semibold))
                .foregroundStyle(effect == .deny ? Theme.riskHigh
                                 : effect == .ask ? Theme.riskMed : Theme.ok)
        } else {
            Image(systemName: locallyAllowed ? "checkmark.circle.fill" : "nosign")
                .foregroundStyle(locallyAllowed ? Theme.ok : Theme.muted)
        }
    }


    var body: some View {
        List {
            Section {
                HStack(spacing: 11) {
                    AgentGlyph(agent: session.agent, size: 38)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(session.displayTitle).font(.headline)
                        Text(session.historyTimestamp.formatted(date: .long,
                                                                time: .shortened))
                            .font(.caption).foregroundStyle(Theme.muted)
                            .accessibilityLabel(session.historyTimestampLabel)
                    }
                }
                if let summary = session.summary, !summary.isEmpty { Text(summary) }
            }

            Section(L("Recent messages & activity")) {
                if visibleEntries.isEmpty {
                    if !model.connected {
                        Text(L("Waiting for Mac connection to load messages…"))
                            .foregroundStyle(Theme.muted)
                    } else if activitySnapshotKnown {
                        VStack(alignment: .leading, spacing: 8) {
                            Text(L("No messages loaded yet."))
                                .foregroundStyle(Theme.muted)
                            Button(L("Retry load")) {
                                model.clearEmptyActivitySnapshot(sessionId: chatSessionId)
                                model.subscribeSession(chatSessionId, active: true,
                                                       source: "phone-history:\(chatSessionId)")
                            }
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(accent)
                        }
                    } else {
                        HStack(spacing: 8) {
                            ProgressView().controlSize(.small)
                            Text(L("Loading visible events from the Mac…"))
                                .foregroundStyle(Theme.muted)
                        }
                    }
                } else {
                    ForEach(visibleEntries) { entry in
                        VStack(alignment: .leading, spacing: 4) {
                            Label(entry.kind == "tool" ? "Action" : "Message",
                                  systemImage: entry.kind == "tool"
                                  ? "terminal" : "text.bubble")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(entry.kind == "tool"
                                                 ? Theme.muted : Theme.accent(for: session.agent))
                            Text(entry.text)
                                .font(entry.kind == "tool" ? Theme.mono(12) : .system(size: 14))
                                .textSelection(.enabled)
                        }
                        .padding(.vertical, 3)
                    }
                }
            }

            Section(L("Tokens & context")) {
                CompatLabeledContent("Session tokens", value: Format.tokens(session.tokensSession))
                CompatLabeledContent("Last turn", value: Format.tokens(session.tokensLastTurn))
                if let used = session.contextTokensUsed {
                    CompatLabeledContent("Context used", value: Format.tokens(used))
                }
                if let window = session.contextWindow {
                    CompatLabeledContent("Context window", value: Format.tokens(window))
                }
            }

            if let servers = session.mcpServers, !servers.isEmpty {
                Section(L("MCP servers")) {
                    ForEach(servers) { server in
                        HStack(spacing: 10) {
                            MCPBadge(name: server.name, size: 28, server: server)
                            Text(server.displayTitle)
                            Spacer()
                            capabilityState(.mcp, locallyAllowed: server.allowed)
                        }
                    }
                }
            }

            if let skills = session.skills, !skills.isEmpty {
                Section(L("Chat skills")) {
                    ForEach(skills) { skill in
                        HStack(spacing: 10) {
                            Label(skill.name, systemImage: "wand.and.stars")
                            Spacer()
                            capabilityState(.skill, locallyAllowed: skill.allowed != false)
                        }
                    }
                }
            }

            Section(L("Details")) {
                if let cwd = session.cwd { CompatLabeledContent("Folder", value: cwd) }
                if let branch = session.branch { CompatLabeledContent("Branch", value: branch) }
                if let agentModel = session.model { CompatLabeledContent("Model", value: agentModel) }
            }

            Section {
                Button {
                    model.setSessionArchived(session.sessionId, !model.isArchived(session.sessionId))
                } label: {
                    Label(model.isArchived(session.sessionId) ? "Restore from archive" : "Archive on this iPhone",
                          systemImage: model.isArchived(session.sessionId)
                          ? "arrow.uturn.backward" : "archivebox")
                }
            } footer: {
                Text(L("Archive is local to this iPhone and never deletes the source chat on the Mac."))
            }
        }
        .pageNavigationTitle(AgentIdentity.displayName(session.agent))
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            retainCurrentEntries()
            model.subscribeSession(chatSessionId, active: true,
                                   source: "phone-history:\(chatSessionId)")
        }
        .onChange(of: entries.map(\.id)) { _ in retainCurrentEntries() }
        .onDisappear {
            model.subscribeSession(chatSessionId, active: false,
                                   source: "phone-history:\(chatSessionId)")
        }
    }
}

private extension SessionInfo {
    var historyTimestamp: Date {
        Date(timeIntervalSince1970: (lastMessageAt ?? lastActivityAt) / 1_000)
    }

    var historyTimestampLabel: String {
        let kind = lastMessageAt == nil ? L("Last activity") : L("Last message")
        return "\(kind): \(historyTimestamp.formatted(date: .long, time: .shortened))"
    }
}
