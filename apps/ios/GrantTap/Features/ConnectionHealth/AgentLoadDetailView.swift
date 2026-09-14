import SwiftUI

/// One agent on one computer: what it is running right now, and the last hour
/// of what it cost.
///
/// "Claude · 38 % CPU" was the whole story before. The story is forty-three
/// node workers and ten shells, and it was getting warm twenty minutes ago,
/// not now.
struct AgentLoadDetailView: View {
    let room: String
    let agent: String
    @EnvironmentObject private var model: AppModel

    var sample: AgentLoadSample? {
        model.machineLoadByRoom[room]?.agents.first { $0.agent == agent }
    }

    var history: [LoadHistoryPoint] { model.machineLoadHistoryByRoom[room] ?? [] }

    var body: some View {
        List {
            nowSection
            lastHourSection
            processesSection
        }
        .navigationTitle(AgentIdentity.displayName(agent))
    }

    private var nowSection: some View {
        Section {
            if let sample {
                CompatLabeledContent(L("CPU"), value: ConnectionLoadFormat.cpu(sample.cpuPercent))
                CompatLabeledContent(L("Memory"), value: ConnectionLoadFormat.bytes(sample.memoryBytes))
                // Each number opens into its rows: which processes, which chats.
                NavigationLink {
                    AgentProcessListView(room: room, agent: agent)
                } label: {
                    CompatLabeledContent(L("Processes"), value: "\(sample.processes)")
                }
                .accessibilityIdentifier("load.open-processes")
                NavigationLink {
                    AgentChatLoadView(room: room, agent: agent)
                } label: {
                    CompatLabeledContent(L("Chats"), value: "\(sample.sessions)")
                }
                .accessibilityIdentifier("load.open-chats")
                NavigationLink {
                    AgentDiskView(room: room, agent: agent)
                } label: {
                    CompatLabeledContent(
                        L("Disk"), value: sample.disk.map { ConnectionLoadFormat.bytes($0.totalBytes) } ?? "—"
                    )
                }
                .accessibilityIdentifier("load.open-disk")
                CompatLabeledContent(L("Scan"), value: ConnectionLoadFormat.duration(ms: sample.scanMs))
                CompatLabeledContent(L("Tokens"), value: ConnectionLoadFormat.tokens(sample.tokensRecent))
            } else {
                Text(L("This agent is not running on that computer right now."))
                    .foregroundStyle(Theme.muted)
            }
        } header: {
            Text(L("Now"))
        }
    }

    @ViewBuilder private var lastHourSection: some View {
        let now = Date().timeIntervalSince1970 * 1_000
        let since = now - LoadHistory.windowMs
        let cpu = LoadHistory.series(history, slots: 30, since: since, until: now) { $0.cpu(of: agent) }
        let memory = LoadHistory.series(history, slots: 30, since: since, until: now) { $0.memory(of: agent) }
        let processes = LoadHistory.series(history, slots: 30, since: since, until: now) {
            $0.processes(of: agent).map(Double.init)
        }
        Section {
            VStack(alignment: .leading, spacing: 4) {
                Text(L("Right now")).font(.system(size: 13, weight: .semibold))
                LoadLiveChart(points: history, accent: Theme.accent(for: agent), now: now, format: ConnectionLoadFormat.cpu) {
                    $0.cpu(of: agent)
                }
            }
            if history.count < 2 {
                Text(L("The chart fills in as the computer keeps reporting; it keeps the last hour."))
                    .font(.caption).foregroundStyle(Theme.muted)
            } else {
                chart(L("CPU"), values: cpu) { ConnectionLoadFormat.cpu($0) }
                chart(L("Memory"), values: memory) { ConnectionLoadFormat.bytes($0) }
                chart(L("Processes"), values: processes) { String(format: "%.0f", $0) }
            }
        } header: {
            Text(L("Last hour"))
        }
    }

    private func chart(_ title: String, values: [Double?], format: @escaping (Double) -> String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.system(size: 13, weight: .semibold))
            LoadHistoryChart(
                values: values, accent: Theme.accent(for: agent),
                startLabel: L("an hour ago"), endLabel: L("now"), format: format
            )
        }
    }

    @ViewBuilder private var processesSection: some View {
        if let sample, !sample.topProcesses.isEmpty {
            Section {
                ForEach(sample.topProcesses) { group in
                    groupRow(group, share: Self.share(of: group, among: sample.topProcesses))
                }
            } header: {
                Text(L("What it runs"))
            } footer: {
                Text(L("Everything the agent started counts as the agent: its shells, its node workers, the tools it called. The heaviest kinds are listed; each bar is that kind's share of the agent's CPU."))
            }
        }
    }

    private func groupRow(_ group: ProcessGroupLoad, share: Double) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(group.name).font(Theme.mono(14, .semibold))
                    Text(LPlural(group.count, one: "%d process", many: "%d processes"))
                        .font(.caption).foregroundStyle(Theme.muted)
                }
                Spacer()
                Text(ConnectionLoadFormat.cpuAndMemory(cpuPercent: group.cpuPercent, memoryBytes: group.memoryBytes))
                    .font(Theme.mono(13, .regular)).foregroundStyle(Theme.muted)
            }
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Capsule().fill(Theme.line)
                    Capsule()
                        .fill(Theme.accent(for: agent))
                        .frame(width: max(2, geometry.size.width * share))
                }
            }
            .frame(height: 4)
        }
        .padding(.vertical, 2)
    }

    /// A kind's share of the agent's CPU; when nothing is busy, of its memory,
    /// so an idle agent still shows what is holding the space.
    static func share(of group: ProcessGroupLoad, among groups: [ProcessGroupLoad]) -> Double {
        let cpu = groups.reduce(0.0) { $0 + Double($1.cpuPercent) }
        if cpu > 0 { return min(1, Double(group.cpuPercent) / cpu) }
        let memory = groups.reduce(0.0) { $0 + Double($1.memoryBytes) }
        return memory > 0 ? min(1, Double(group.memoryBytes) / memory) : 0
    }
}
