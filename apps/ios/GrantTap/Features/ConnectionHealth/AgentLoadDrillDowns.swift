import SwiftUI

/// The rows behind an agent's numbers: its processes one by one, its chats,
/// and what it keeps on the disk.
///
/// "Processes 33" was a number that could not be opened, and the question it
/// raised — which of them, for which chat, eating what — went unanswered.

@MainActor
private func chatTitle(_ sessionId: String, in model: AppModel) -> String {
    let session = (model.sessions + model.allSessionHistory).first { $0.sessionId == sessionId }
    return session?.displayTitle ?? String(sessionId.prefix(8))
}

@MainActor
private func agentSample(_ model: AppModel, room: String, agent: String) -> AgentLoadSample? {
    model.machineLoadByRoom[room]?.agents.first { $0.agent == agent }
}

private struct ShareBar: View {
    let fraction: Double
    let accent: Color

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                Capsule().fill(Theme.line)
                Capsule().fill(accent).frame(width: max(2, geometry.size.width * min(1, max(0, fraction))))
            }
        }
        .frame(height: 4)
    }
}

/// Each process, heaviest first.
struct AgentProcessListView: View {
    let room: String
    let agent: String
    @EnvironmentObject private var model: AppModel

    var sample: AgentLoadSample? { agentSample(model, room: room, agent: agent) }

    var body: some View {
        List {
            Section {
                if let sample, !sample.processList.isEmpty {
                    ForEach(sample.processList) { row in processRow(row, of: sample) }
                } else {
                    Text(L("The computer has not listed this agent's processes yet."))
                        .foregroundStyle(Theme.muted)
                }
            } header: {
                if let sample, !sample.processList.isEmpty {
                    Text(String(format: L("%d of %d, heaviest first"), sample.processList.count, sample.processes))
                }
            } footer: {
                Text(L("Each row is one process as the system reports it. A process is tied to a chat when the agent told GrantTap which chat it works for."))
            }
        }
        .navigationTitle(L("Processes"))
    }

    /// A process's share of the agent's CPU, or of its memory when nothing is busy.
    static func share(of row: ProcessLoadRow, in sample: AgentLoadSample) -> Double {
        if sample.cpuPercent > 0 { return row.cpuPercent / sample.cpuPercent }
        return sample.memoryBytes > 0 ? row.memoryBytes / sample.memoryBytes : 0
    }

    private func processRow(_ row: ProcessLoadRow, of sample: AgentLoadSample) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(row.name).font(Theme.mono(14, .semibold)).foregroundStyle(Theme.ink)
                // Verbatim: a pid is an identifier, not a quantity to group by thousands.
                Text(verbatim: "#\(row.pid)").font(.caption2).foregroundStyle(Theme.muted)
                Spacer()
                Text(ConnectionLoadFormat.cpuAndMemory(cpuPercent: row.cpuPercent, memoryBytes: row.memoryBytes))
                    .font(Theme.mono(13, .regular)).foregroundStyle(Theme.muted)
            }
            if let detail = row.detail {
                Text(detail).font(Theme.mono(11, .regular)).foregroundStyle(Theme.muted).lineLimit(2)
            }
            if let sessionId = row.sessionId {
                Label(chatTitle(sessionId, in: model), systemImage: "bubble.left")
                    .font(.caption).foregroundStyle(Theme.accent(for: agent)).lineLimit(1)
            }
            ShareBar(fraction: Self.share(of: row, in: sample), accent: Theme.accent(for: agent))
        }
        .padding(.vertical, 2)
        .accessibilityIdentifier("load.process.\(row.pid)")
    }
}

/// One chat of the agent on that computer, with what its processes cost.
struct AgentChatLoadRow: Identifiable, Equatable {
    let sessionId: String
    let title: String
    let load: ChatProcessLoad?
    let tokens: Int
    let contextPercent: Int?
    let state: String?
    var id: String { sessionId }
}

enum AgentChatLoadRows {
    /// The chats the computer measured, joined with the chats the phone knows
    /// for that agent, heaviest first; a chat with no measured process still
    /// appears, because it is open there and a person may wonder why it is quiet.
    static func rows(sample: AgentLoadSample, sessions: [SessionInfo]) -> [AgentChatLoadRow] {
        let known = sessions.filter { $0.agent == sample.agent }
        var byId: [String: SessionInfo] = [:]
        for session in known where byId[session.sessionId] == nil { byId[session.sessionId] = session }
        var ids: [String] = sample.chats.map(\.sessionId)
        for session in known where !ids.contains(session.sessionId) { ids.append(session.sessionId) }
        let loads = Dictionary(uniqueKeysWithValues: sample.chats.map { ($0.sessionId, $0) })
        return ids.map { id in
            let session = byId[id]
            let percent: Int? = session.flatMap { info in
                guard let used = info.contextTokensUsed, let window = info.contextWindow, window > 0 else { return nil }
                return Int((Double(used) / Double(window) * 100).rounded())
            }
            return AgentChatLoadRow(
                sessionId: id, title: session?.displayTitle ?? String(id.prefix(8)), load: loads[id],
                tokens: session?.tokensSession ?? 0, contextPercent: percent, state: session?.state
            )
        }.sorted { left, right in
            let l = left.load, r = right.load
            if (l?.cpuPercent ?? -1) != (r?.cpuPercent ?? -1) { return (l?.cpuPercent ?? -1) > (r?.cpuPercent ?? -1) }
            if (l?.memoryBytes ?? -1) != (r?.memoryBytes ?? -1) { return (l?.memoryBytes ?? -1) > (r?.memoryBytes ?? -1) }
            return left.tokens > right.tokens
        }
    }

    static func share(of row: AgentChatLoadRow, in rows: [AgentChatLoadRow]) -> Double {
        let cpu = rows.reduce(0.0) { $0 + ($1.load?.cpuPercent ?? 0) }
        if cpu > 0 { return (row.load?.cpuPercent ?? 0) / cpu }
        let memory = rows.reduce(0.0) { $0 + ($1.load?.memoryBytes ?? 0) }
        return memory > 0 ? (row.load?.memoryBytes ?? 0) / memory : 0
    }
}

struct AgentChatLoadView: View {
    let room: String
    let agent: String
    @EnvironmentObject private var model: AppModel

    var rows: [AgentChatLoadRow] {
        guard let sample = agentSample(model, room: room, agent: agent) else { return [] }
        return AgentChatLoadRows.rows(sample: sample, sessions: model.sessions + model.allSessionHistory)
    }

    var body: some View {
        let rows = rows
        List {
            Section {
                if rows.isEmpty {
                    Text(L("No chats of this agent are known on that computer."))
                        .foregroundStyle(Theme.muted)
                } else {
                    ForEach(rows) { row in chatRow(row, in: rows) }
                }
            } footer: {
                Text(L("A chat's load is the processes it started. A chat with no number is open on that computer but ran nothing GrantTap could tie to it."))
            }
        }
        .navigationTitle(L("Chats"))
    }

    private func chatRow(_ row: AgentChatLoadRow, in rows: [AgentChatLoadRow]) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline) {
                Text(row.title).font(.system(size: 14, weight: .semibold)).foregroundStyle(Theme.ink).lineLimit(1)
                Spacer()
                if let load = row.load {
                    Text(ConnectionLoadFormat.cpuAndMemory(cpuPercent: load.cpuPercent, memoryBytes: load.memoryBytes))
                        .font(Theme.mono(13, .regular)).foregroundStyle(Theme.muted)
                }
            }
            Text(detail(row)).font(.caption).foregroundStyle(Theme.muted)
            ShareBar(fraction: AgentChatLoadRows.share(of: row, in: rows), accent: Theme.accent(for: agent))
        }
        .padding(.vertical, 2)
        .accessibilityIdentifier("load.chat.\(row.sessionId)")
    }

    static func detailParts(_ row: AgentChatLoadRow) -> [String] {
        var parts: [String] = []
        if let load = row.load {
            parts.append(LPlural(load.processes, one: "%d process", many: "%d processes"))
        } else {
            parts.append(L("no measured process"))
        }
        if row.tokens > 0 { parts.append("\(Format.tokens(row.tokens)) tok") }
        if let percent = row.contextPercent { parts.append(String(format: L("ctx %d%%"), percent)) }
        if let state = row.state, !state.isEmpty { parts.append(L(state)) }
        return parts
    }

    private func detail(_ row: AgentChatLoadRow) -> String {
        Self.detailParts(row).joined(separator: " · ")
    }
}

/// What the agent keeps on the disk.
struct AgentDiskView: View {
    let room: String
    let agent: String
    @EnvironmentObject private var model: AppModel

    var disk: AgentDiskUsage? { agentSample(model, room: room, agent: agent)?.disk }

    var body: some View {
        List {
            if let disk {
                Section {
                    CompatLabeledContent(L("Total"), value: ConnectionLoadFormat.bytes(disk.totalBytes))
                    ForEach(disk.entries) { entry in entryRow(entry, of: disk) }
                } footer: {
                    Text(String(format: L("Measured %@ with du, in the agent's own folders only. The computer measures again every ten minutes."), measuredAgo(disk)))
                }
            } else {
                Section {
                    Text(L("Not measured yet. The computer measures the agent's folders every ten minutes; the first number arrives with a later sample."))
                        .foregroundStyle(Theme.muted)
                }
            }
        }
        .navigationTitle(L("Disk"))
    }

    private func measuredAgo(_ disk: AgentDiskUsage) -> String {
        let seconds = Int(max(0, Date().timeIntervalSince1970 * 1_000 - disk.measuredAt) / 1_000)
        return ConnectionLoadFormat.age(seconds: seconds)
    }

    private func entryRow(_ entry: DiskUsageEntry, of disk: AgentDiskUsage) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline) {
                Text(entry.path == "…" ? L("everything else") : entry.path)
                    .font(Theme.mono(13, .semibold)).foregroundStyle(Theme.ink).lineLimit(1).truncationMode(.middle)
                Spacer()
                Text(ConnectionLoadFormat.bytes(entry.bytes)).font(Theme.mono(13, .regular)).foregroundStyle(Theme.muted)
            }
            ShareBar(fraction: disk.totalBytes > 0 ? entry.bytes / disk.totalBytes : 0, accent: Theme.accent(for: agent))
        }
        .padding(.vertical, 2)
    }
}
