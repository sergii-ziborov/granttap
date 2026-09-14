import Foundation

/// Each table a report carries: tools, kinds, wrong turns, executions, load.
/// One shape — a title, columns, and rows already turned into text.
extension ReportBuilder {
    // MARK: Tables

    static func toolsTable(_ events: [CapabilityUsageEvent]) -> ProjectReport.Table {
        let rows = UsageSummaries(events: events, totals: []).rows.map { summary -> [String] in
            [
                kindLabel(summary.kind), summary.name, "\(summary.count)", "\(summary.failures)",
                summary.cpuTimeMs.map { CapabilityResourceFormat.duration($0) } ?? "",
                summary.peakMemoryBytes.map { CapabilityResourceFormat.bytes($0) } ?? "",
                summary.averageDurationMs.map { CapabilityResourceFormat.duration($0) } ?? "",
            ]
        }
        return .init(
            title: L("Tools"),
            columns: [L("Kind"), L("Name"), L("Calls"), L("Failed"), L("CPU"), L("Peak memory"), L("Avg. duration")],
            rows: rows.isEmpty ? [[L("No observed tool calls"), "", "", "", "", "", ""]] : rows
        )
    }

    static func kindTable(_ events: [CapabilityUsageEvent], kind: CapabilityUsageKind, title: String) -> ProjectReport.Table? {
        let grouped = Dictionary(grouping: events.filter { $0.kind == kind }, by: \.name)
        guard !grouped.isEmpty else { return nil }
        struct Line { let name: String; let calls: Int; let failed: Int; let lastAt: Double }
        var lines: [Line] = []
        for (name, calls) in grouped {
            let failed = calls.filter { $0.effectiveOutcome == .error }.count
            lines.append(Line(name: name, calls: calls.count, failed: failed, lastAt: calls.map(\.createdAt).max() ?? 0))
        }
        lines.sort { left, right in
            if left.calls != right.calls { return left.calls > right.calls }
            return left.name < right.name
        }
        let rows: [[String]] = lines.map { [$0.name, String($0.calls), String($0.failed), stamp($0.lastAt)] }
        return .init(title: title, columns: [L("Name"), L("Calls"), L("Failed"), L("Last used")], rows: rows)
    }

    static func wrongTurnsTable(_ calls: [CapabilityUsageEvent], meshEvents: [ProjectMeshEvent]) -> ProjectReport.Table {
        var rows: [(Double, [String])] = calls.map { event in
            (event.createdAt, [
                stamp(event.createdAt),
                event.effectiveOutcome == .cancelled ? L("Cancelled call") : L("Failed call"),
                "\(kindLabel(event.kind)) · \(event.name)",
                event.errorClass ?? event.commandPreview ?? "",
            ])
        }
        rows += meshEvents.map { event in
            (event.createdAt, [
                stamp(event.createdAt), meshLabel(event.eventType), event.sourceSessionId,
                event.payload.reason ?? event.payload.resource ?? "",
            ])
        }
        return .init(
            title: L("Wrong turns"), columns: [L("When"), L("What"), L("Where"), L("Detail")],
            rows: rows.sorted { $0.0 < $1.0 }.map(\.1)
        )
    }

    static func executionsTable(
        _ executions: [ExecutionSessionLink], sessions: [SessionInfo], computerName: (String) -> String
    ) -> ProjectReport.Table {
        var rows = executions.sorted { $0.startedAt < $1.startedAt }.map { execution -> [String] in
            let session = sessions.first { $0.sessionId == execution.sessionId }
            return [
                AgentIdentity.displayName(execution.provider), computerName(execution.computerId),
                execution.branch ?? "", stamp(execution.startedAt), stamp(execution.lastSeenAt),
                execution.endedAt.map(stamp) ?? L("open"),
                session.map { Format.tokens($0.tokensSession) } ?? "",
            ]
        }
        if executions.isEmpty {
            rows = sessions.map { session in
                [AgentIdentity.displayName(session.agent), session.computerId.map(computerName) ?? "",
                 session.branch ?? "", stamp(session.startedAt), stamp(session.lastActivityAt),
                 session.state == "working" ? L("open") : session.state, Format.tokens(session.tokensSession)]
            }
        }
        return .init(
            title: L("Executions"),
            columns: [L("Agent"), L("Computer"), L("Branch"), L("Started"), L("Last active"), L("Ended"), L("Tokens")],
            rows: rows
        )
    }

    /// Processor and memory of the agents that did the work, from the load
    /// samples the phone kept: an average, the worst moment, and how many
    /// samples say so.
    static func loadTable(
        executions: [ExecutionSessionLink], sessions: [SessionInfo], inputs: ReportInputs
    ) -> ProjectReport.Table? {
        let pairs = Set(executions.map { "\($0.computerId)\u{1f}\(AgentIdentity.normalize($0.provider))" }
            + sessions.compactMap { session in
                session.computerId.map { "\($0)\u{1f}\(AgentIdentity.normalize(session.agent))" }
            })
        var rows: [[String]] = []
        for pair in pairs.sorted() {
            let parts = pair.split(separator: "\u{1f}").map(String.init)
            guard parts.count == 2, let points = inputs.loadHistory[parts[0]], !points.isEmpty else { continue }
            let samples = points.compactMap { point -> (Double, Double)? in
                guard let cpu = point.cpu(of: parts[1]), let memory = point.memory(of: parts[1]) else { return nil }
                return (cpu, memory)
            }
            guard !samples.isEmpty else { continue }
            let average = samples.map(\.0).reduce(0, +) / Double(samples.count)
            rows.append([
                inputs.computerName(parts[0]), AgentIdentity.displayName(parts[1]),
                String(format: "%.0f%%", average), String(format: "%.0f%%", samples.map(\.0).max() ?? 0),
                CapabilityResourceFormat.bytes(Int(samples.map(\.1).max() ?? 0)),
                "\(samples.count)",
            ])
        }
        guard !rows.isEmpty else { return nil }
        return .init(
            title: L("Machine load"),
            columns: [L("Computer"), L("Agent"), L("Avg. CPU"), L("Peak CPU"), L("Peak memory"), L("Samples")],
            rows: rows, footnote: L("From the load samples this phone kept while it was connected.")
        )
    }

    /// Disk the agents' own folders take, from the latest load report.
    static func diskFigure(
        executions: [ExecutionSessionLink], sessions: [SessionInfo], latest: [String: MachineLoad]
    ) -> ProjectReport.Figure? {
        let agents = Set(executions.map { AgentIdentity.normalize($0.provider) }
            + sessions.map { AgentIdentity.normalize($0.agent) })
        var total = 0.0
        var parts: [String] = []
        for (computer, load) in latest.sorted(by: { $0.key < $1.key }) {
            for sample in load.agents where agents.contains(AgentIdentity.normalize(sample.agent)) {
                guard let disk = sample.disk else { continue }
                total += disk.totalBytes
                parts.append("\(AgentIdentity.shortName(sample.agent)) \(CapabilityResourceFormat.bytes(Int(disk.totalBytes))) · \(computer)")
            }
        }
        guard total > 0 else { return nil }
        return .init(label: L("Disk"), value: CapabilityResourceFormat.bytes(Int(total)), note: parts.joined(separator: ", "))
    }

    // MARK: Words

    static func kindLabel(_ kind: CapabilityUsageKind) -> String {
        switch kind {
        case .mcp: return "MCP"
        case .skill: return L("Skill")
        case .cli: return L("CLI")
        }
    }

    static func meshLabel(_ type: String) -> String {
        switch type {
        case "TASK_BLOCKED": return L("Task blocked")
        case "HANDOFF_REJECTED": return L("Handoff failed")
        case "CONFLICT": return L("Conflict detected")
        default: return type
        }
    }

    static func stamp(_ epochMs: Double) -> String {
        guard epochMs > 0 else { return "" }
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .short
        return formatter.string(from: Date(timeIntervalSince1970: epochMs / 1_000))
    }
}