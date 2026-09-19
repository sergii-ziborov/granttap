import SwiftUI

/// What the header pill can only hint at: why the link reads the way it does,
/// and which agent is actually making the computer work.
struct ConnectionDetailSheet: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var model: AppModel

    var body: some View {
        CompatNavigationStack {
            ZStack {
                Theme.bg.ignoresSafeArea()
                List {
                    linkSection
                    ForEach(model.connectionRegistry.connections, id: \.id) { connection in
                        computerSection(connection)
                        toolsSection(connection)
                    }
                    linkLogSection
                }
            }
            .navigationTitle(L("Connection"))
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(L("Done")) { dismiss() }
                }
            }
        }
    }

    private var linkSection: some View {
        let snap = model.connectionSnapshot
        return Section {
            CompatLabeledContent(L("Status")) {
                HStack(spacing: 6) {
                    Circle().fill(snap.statusColor).frame(width: 8, height: 8)
                    Text(snap.statusTitle).foregroundStyle(Theme.muted)
                }
            }
            if let machine = snap.machineName {
                CompatLabeledContent(L("Computer")) {
                    Text(machine).foregroundStyle(Theme.muted)
                }
            }
            if let room = snap.roomShort {
                CompatLabeledContent(L("Room")) {
                    Text(room).font(Theme.mono(13, .regular)).foregroundStyle(Theme.muted)
                }
            }
            CompatLabeledContent(L("Chat list updated")) {
                Text(ConnectionLoadFormat.age(seconds: snap.catalogAgeSeconds))
                    .foregroundStyle(Theme.muted)
            }
        } header: {
            Text(L("This link"))
        } footer: {
            Text(snap.detail)
        }
    }

    private var linkLogSection: some View {
        Section {
            if model.log.isEmpty {
                Text(L("No link events yet. Scan or Reconnect, then this list shows the room, socket, hello, and heartbeat."))
                    .foregroundStyle(Theme.muted)
            } else {
                ForEach(Array(model.log.prefix(20).enumerated()), id: \.offset) { _, line in
                    Text(line)
                        .font(Theme.mono(12, .regular))
                        .foregroundStyle(Theme.ink)
                        .textSelection(.enabled)
                }
            }
        } header: {
            Text(L("Link log"))
        } footer: {
            Text(L("Same room on Reconnect is expected. Offline means this iPhone has no socket, or the Mac has not published a heartbeat."))
        }
    }

    /// The tools that computer runs, each with its version and its own updater.
    @ViewBuilder private func toolsSection(_ connection: LinkedComputer) -> some View {
        let tools = model.agentIntegrationsByRoom[connection.id] ?? []
        if !tools.isEmpty {
            let computer = connection.lastMachineName.isEmpty ? connection.displayName : connection.lastMachineName
            Section {
                ForEach(tools) { info in
                    ToolVersionRow(
                        info: info,
                        progress: model.toolUpdate(room: connection.id, agent: info.agent),
                        computerName: computer
                    ) {
                        _ = model.updateTool(agent: info.agent, room: connection.id)
                    }
                }
            } header: {
                Text(L("Tools on this computer"))
            } footer: {
                Text(L("Each tool is updated by its own updater, run on that computer. GrantTap never downloads a tool itself."))
            }
        }
    }

    private func computerSection(_ connection: LinkedComputer) -> some View {
        let load = model.machineLoadByRoom[connection.id]
        let snap = model.snapshotForConnection(connection)
        return Section {
            // Status and its repair live on the same row: a computer you can see
            // is broken should be fixable without hunting through settings.
            HStack(spacing: 8) {
                Circle().fill(snap.statusColor).frame(width: 8, height: 8)
                Text(snap.statusTitle)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Theme.ink)
                if let age = snap.catalogAgeSeconds {
                    Text(ConnectionLoadFormat.age(seconds: age))
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.muted)
                }
                Spacer()
                if ConnectionSnapshot.needsAttention(snap.phase) {
                    Button(snap.primaryActionTitle) {
                        Task { await model.repairConnection(roomId: connection.id) }
                    }
                    .buttonStyle(.borderless)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Theme.riskMed)
                }
            }
            if let load {
                CompatLabeledContent(L("GrantTap itself (30s avg)")) {
                    Text(ConnectionLoadFormat.cpuAndMemory(
                        cpuPercent: load.monitorCpuPercent,
                        memoryBytes: load.monitorMemoryBytes
                    ))
                    .foregroundStyle(Theme.muted)
                }
                // The hour behind the number: the whole machine's agent CPU.
                let history = model.loadHistory(room: connection.id)
                if history.count >= 2 {
                    let now = Date().timeIntervalSince1970 * 1_000
                    VStack(alignment: .leading, spacing: 4) {
                        Text(L("Agents, right now")).font(.system(size: 13, weight: .semibold))
                        LoadLiveChart(points: history, accent: Theme.ink, now: now, format: ConnectionLoadFormat.cpu) { $0.agentCpuTotal }
                    }
                    VStack(alignment: .leading, spacing: 4) {
                        Text(L("Agents, last hour")).font(.system(size: 13, weight: .semibold))
                        LoadHistoryChart(
                            values: LoadHistory.series(history, slots: 30, since: now - LoadHistory.windowMs, until: now) {
                                $0.agentCpuTotal
                            },
                            accent: Theme.codex, startLabel: L("an hour ago"), endLabel: L("now"),
                            format: ConnectionLoadFormat.cpu
                        )
                    }
                }
                if load.agents.isEmpty {
                    Text(L("No agent activity measured yet."))
                        .foregroundStyle(Theme.muted)
                } else {
                    // Every agent opens: what it runs, and its own hour.
                    ForEach(load.agents) { sample in
                        NavigationLink {
                            AgentLoadDetailView(room: connection.id, agent: sample.agent)
                        } label: {
                            AgentLoadRow(sample: sample, share: load.cpuShare(of: sample))
                        }
                    }
                }
            } else {
                Text(snap.phase == .live
                     ? L("Waiting for the first load report from this computer.")
                     : L("Load is reported only while the computer is Live."))
                    .foregroundStyle(Theme.muted)
            }
        } header: {
            Text(connection.lastMachineName.isEmpty
                 ? connection.displayName
                 : connection.lastMachineName)
        } footer: {
            if load != nil {
                Text(L("CPU and memory come from each agent's own processes, as the system averages them. Scan time is what GrantTap spends reading that agent's logs. Tokens are model spend. They are measured separately and do not add up to one number. GrantTap's own CPU is averaged over 30 seconds, so a brief scan does not read as a busy machine."))
            }
        }
    }
}
