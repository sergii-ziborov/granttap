import Foundation

/// A run of consecutive tool calls, read as one line.
///
/// A transcript of work is mostly work: a dozen tool rows in a row push the
/// message that explains them off the screen. The run reads as what it did —
/// "Created a file, ran 3 commands, used ToolSearch" — and opens to the
/// steps, each to its own detail, the way the Claude app shows it.
struct ChatActivityRun: Identifiable, Equatable {
    let entries: [ActivityEntry]

    /// Anchored on the first call, so a history tap still finds the run.
    var id: String { "run:\(entries.first?.id ?? "")" }

    var calls: Int { entries.count }
    var createdAt: Double { entries.first?.createdAt ?? 0 }
    var steps: [ActivityStep] { entries.map(ActivityStep.init) }

    /// "Created a file, ran a command, used ToolSearch".
    var sentence: String { ActivityStep.sentence(steps) }

    private var capabilities: [ObservedCapability] {
        entries.flatMap { $0.capabilities ?? [] }
    }

    /// Context tokens add up: each call spends its own.
    var tokens: Int {
        entries.reduce(0) { $0 + ($1.estimatedContextTokens ?? 0) }
    }

    /// Processor time adds up the same way, and is the honest "how much CPU".
    var cpuTimeMs: Int? {
        let values = capabilities.compactMap { $0.resource?.effectiveCpuTimeMs }
        return values.isEmpty ? nil : values.reduce(0, +)
    }

    /// Memory is a level, not a total, so the run reports its worst moment.
    var peakMemoryBytes: Int? {
        capabilities.compactMap { $0.resource?.effectivePeakRssBytes }.max()
    }

    /// Wall time the run occupied, which is not the same as processor time.
    var durationMs: Int? {
        let values = entries.compactMap { entry in
            entry.durationMs ?? entry.capabilities?.first?.durationMs
        }
        return values.isEmpty ? nil : values.reduce(0, +)
    }

    var failures: Int {
        entries.filter { entry in
            entry.outcome == .error
                || (entry.capabilities ?? []).contains { $0.outcome == .error }
        }.count
    }

    /// What the run cost, on one line, or nothing.
    var metricsLine: String? {
        let parts = CliCallMetrics.parts(
            tokens: tokens, cpuTimeMs: cpuTimeMs, peakMemoryBytes: peakMemoryBytes, durationMs: durationMs
        )
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }
}

/// One call of a run, as a person reads it: what was done, to what.
struct ActivityStep: Identifiable, Equatable {
    enum Kind: Equatable {
        case created, edited, read, ran, searched, fetched, delegated, used
    }

    let entry: ActivityEntry
    var id: String { entry.id }

    var tool: String { (entry.toolName ?? "").trimmingCharacters(in: .whitespacesAndNewlines) }

    var kind: Kind {
        if entry.mcpServer != nil || entry.skill != nil { return .used }
        if entry.isShellCall { return .ran }
        switch tool.lowercased().split(whereSeparator: { $0 == "." || $0 == ":" || $0 == "/" }).last.map(String.init) ?? "" {
        case "write", "write_file", "create_file": return .created
        case "edit", "multiedit", "notebookedit", "edit_file", "apply_patch", "str_replace_editor": return .edited
        case "read", "read_file", "view": return .read
        case "glob", "grep", "search", "codebase_search", "list_dir", "find": return .searched
        case "webfetch", "websearch", "fetch", "web_search": return .fetched
        case "task", "agent", "subagent": return .delegated
        default: return .used
        }
    }

    /// "Created", "Ran", "Used ToolSearch": the verb, with the tool when the
    /// verb alone would not say which.
    var title: String {
        switch kind {
        case .created: return L("Created")
        case .edited: return L("Edited")
        case .read: return L("Read")
        case .ran: return L("Ran")
        case .searched: return L("Searched")
        case .fetched: return L("Fetched")
        case .delegated: return L("Delegated")
        case .used: return String(format: L("Used %@"), usedName)
        }
    }

    /// The file, the description, the command, or the query.
    var subject: String? {
        switch kind {
        case .created, .edited, .read:
            return ToolRowLabel.subject(of: entry) ?? bodyLine
        case .ran:
            return entry.summary ?? bodyLine
        case .delegated:
            return entry.summary ?? bodyLine
        case .searched, .fetched:
            return entry.summary ?? bodyLine
        case .used:
            if let summary = entry.summary { return summary }
            guard let server = entry.mcpServer else { return nil }
            return argumentLine ?? server
        }
    }

    /// What an MCP call was given, without repeating what it is called: the
    /// "server/tool" line the computer writes for a bare call says nothing new.
    private var argumentLine: String? {
        guard let line = bodyLine else { return nil }
        let leaf = tool.lowercased().split(separator: "_").last.map(String.init) ?? ""
        if let server = entry.mcpServer, line.lowercased() == "\(server.lowercased())/\(tool.lowercased().replacingOccurrences(of: "mcp__\(server.lowercased())__", with: ""))" {
            return nil
        }
        let words = line.split(separator: ":", maxSplits: 1).map(String.init)
        if words.count == 2, !leaf.isEmpty, words[0].lowercased().replacingOccurrences(of: " ", with: "_").hasSuffix(leaf) {
            let rest = words[1].trimmingCharacters(in: .whitespaces)
            return rest.isEmpty ? nil : rest
        }
        return line
    }

    /// The tool's name as a person would say it: "Tabs Context Mcp", "ToolSearch".
    var usedName: String {
        if let skill = entry.skill { return "\(L("skill")) \(skill)" }
        var name = tool
        if let server = entry.mcpServer {
            let prefix = "mcp__\(server)__"
            if name.lowercased().hasPrefix(prefix.lowercased()) { name = String(name.dropFirst(prefix.count)) }
            if name.isEmpty { name = server }
        }
        let words = name.split(whereSeparator: { $0 == "_" || $0 == "-" }).map { word -> String in
            let text = String(word)
            return text.first.map { String($0).uppercased() + text.dropFirst() } ?? text
        }
        return words.isEmpty ? L("a tool") : words.joined(separator: " ")
    }

    var icon: String {
        switch kind {
        case .created, .edited: return "square.and.pencil"
        case .read: return "doc.text"
        case .ran: return "terminal"
        case .searched: return "magnifyingglass"
        case .fetched: return "globe"
        case .delegated: return "person.2"
        case .used: return entry.mcpServer != nil ? "shippingbox" : "wrench.and.screwdriver"
        }
    }

    var failed: Bool {
        entry.outcome == .error || (entry.capabilities ?? []).contains { $0.outcome == .error }
    }

    private var bodyLine: String? {
        let line = entry.oneLinePreview.trimmingCharacters(in: .whitespacesAndNewlines)
        return line.isEmpty ? nil : line
    }

    /// The run in one sentence: verbs with counts, in the order they first
    /// happened, the tools by name.
    static func sentence(_ steps: [ActivityStep]) -> String {
        var order: [Kind] = []
        var counts: [Kind: Int] = [:]
        var used: [String] = []
        for step in steps {
            if counts[step.kind] == nil { order.append(step.kind) }
            counts[step.kind, default: 0] += 1
            if step.kind == .used, !used.contains(step.usedName) { used.append(step.usedName) }
        }
        let parts = order.map { kind -> String in
            let count = counts[kind] ?? 0
            switch kind {
            case .created: return LPlural(count, one: "created a file", many: "created %d files")
            case .edited: return LPlural(count, one: "edited a file", many: "edited %d files")
            case .read: return LPlural(count, one: "read a file", many: "read %d files")
            case .ran: return LPlural(count, one: "ran a command", many: "ran %d commands")
            case .searched: return LPlural(count, one: "searched once", many: "searched %d times")
            case .fetched: return LPlural(count, one: "fetched a page", many: "fetched %d pages")
            case .delegated: return LPlural(count, one: "delegated once", many: "delegated %d times")
            case .used:
                switch used.count {
                case 0: return L("used a tool")
                case 1: return String(format: L("used %@"), used[0])
                case 2: return String(format: L("used %@ and %@"), used[0], used[1])
                default: return String(format: L("used %@, %@ and %d more"), used[0], used[1], used.count - 2)
                }
            }
        }
        let joined = parts.joined(separator: ", ")
        guard let first = joined.first else { return L("Did nothing yet") }
        return String(first).uppercased() + joined.dropFirst()
    }
}

/// Which transcript rows are tool calls, and where the runs are.
enum ChatActivityGrouping {
    static func isToolCall(_ entry: ActivityEntry) -> Bool {
        entry.kind == "tool"
    }

    /// Fold consecutive tool calls, leaving everything else exactly where it was.
    static func rows(_ items: [CombinedTaskTimelineItem]) -> [ChatTimelineRow] {
        var rows: [ChatTimelineRow] = []
        var run: [ActivityEntry] = []

        func flush() {
            if !run.isEmpty { rows.append(.run(ChatActivityRun(entries: run))) }
            run = []
        }

        for item in items {
            if case .activity(let entry) = item, isToolCall(entry) {
                run.append(entry)
                continue
            }
            flush()
            rows.append(.item(item))
        }
        flush()
        return rows
    }
}

/// One row of the chat: something on its own, or a folded run of tool calls.
enum ChatTimelineRow: Identifiable {
    case item(CombinedTaskTimelineItem)
    case run(ChatActivityRun)

    var id: String {
        switch self {
        case .item(let item): return item.id
        case .run(let run): return run.id
        }
    }
}
