import Foundation

/// The command a shell call ran, as a person would name it.
///
/// "Bash" says which tool was used; "git", "npm", "xcodebuild" say what was
/// done. The Mac names a call the same way, and this is the same rule for
/// the calls it did not name: skip what only sets up the command — `cd`,
/// variables, `sudo` — and keep the first real word, without its path.
enum ShellCommandName {
    private static let wrappers: Set<String> = ["sudo", "env", "time", "nohup", "exec", "command", "builtin", "nice"]
    /// Keywords that introduce the command after them: "then rm" ran rm.
    private static let leaders: Set<String> = ["then", "do", "else", "elif", "!", "{", "("]
    /// Words that structure a script and run nothing a person would name.
    private static let setup: Set<String> = [
        "cd", "export", "set", "source", ".", "pushd", "popd", "unset", "alias", "unalias",
        "if", "for", "while", "until", "case", "select", "function", "fi", "done", "esac", "in",
        "local", "declare", "typeset", "readonly", "eval", "wait", "shift", "return", "exit",
        "true", "false", ":", "read", "trap", "test", "[", "[[", "]", "]]", "}", ")", "shopt", "setopt",
    ]

    static func from(_ command: String?) -> String? {
        guard let command else { return nil }
        let segments = command.components(separatedBy: CharacterSet.newlines)
            .flatMap { $0.components(separatedBy: "&&") }
            .flatMap { $0.components(separatedBy: "||") }
            .flatMap { $0.components(separatedBy: ";") }
            .flatMap { $0.components(separatedBy: "|") }
        for segment in segments {
            var words = segment.split(whereSeparator: { $0 == " " || $0 == "\t" }).map(String.init)
            while let first = words.first, isAssignment(first) || wrappers.contains(first) || leaders.contains(first) {
                words.removeFirst()
            }
            guard let first = words.first else { continue }
            let bare = first.trimmingCharacters(in: CharacterSet(charactersIn: "'\"`()"))
            if bare.isEmpty || bare.hasPrefix("-") || setup.contains(bare) { continue }
            let leaf = bare.split(separator: "/").last.map(String.init) ?? bare
            if leaf.isEmpty || leaf.hasPrefix("-") || isShouting(leaf) || isNumber(leaf) { continue }
            return String(leaf.prefix(64))
        }
        return nil
    }

    /// The tools that run a shell, by the names the agents give them. Mirrors
    /// the Mac: only these calls are CLI, and only their text is a command.
    private static let shellTools: Set<String> = [
        "bash", "shell", "powershell", "terminal", "exec_command", "execute_command",
        "local_shell_call", "run_command", "run_in_terminal", "run_terminal_cmd", "shell_command",
    ]

    static func isShellTool(_ toolName: String?) -> Bool {
        let normalized = (toolName ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !normalized.isEmpty else { return false }
        if shellTools.contains(normalized) { return true }
        let leaf = normalized.split(whereSeparator: { $0 == "." || $0 == ":" || $0 == "/" }).last.map(String.init)
        return leaf.map(shellTools.contains) == true
    }

    /// A transcript row reads "Bash: git status"; the command starts after the tool.
    static func stripToolPrefix(_ text: String, tool: String?) -> String {
        guard let tool = tool?.trimmingCharacters(in: .whitespacesAndNewlines), !tool.isEmpty,
              text.hasPrefix("\(tool): ") else { return text }
        return String(text.dropFirst(tool.count + 2))
    }

    /// A shouting word is a variable, not a command: a preview cut short at
    /// DEVELOPER_DIR must not name the call DEVELOPER_DIR.
    static func isShouting(_ word: String) -> Bool {
        word.range(of: "^[A-Z_][A-Z0-9_]*$", options: .regularExpression) != nil
    }

    /// A number is an argument that lost its command, never a command.
    static func isNumber(_ word: String) -> Bool {
        !word.isEmpty && word.allSatisfy(\.isNumber)
    }

    private static func isAssignment(_ word: String) -> Bool {
        guard let equals = word.firstIndex(of: "="), equals != word.startIndex else { return false }
        let name = word[word.startIndex..<equals]
        return name.allSatisfy { $0.isLetter || $0.isNumber || $0 == "_" }
    }
}

/// What a shell call cost, in the order a person reads it: tokens, processor
/// time, the worst moment for memory, wall time.
enum CliCallMetrics {
    static func parts(tokens: Int, cpuTimeMs: Int?, peakMemoryBytes: Int?, durationMs: Int?) -> [String] {
        var parts: [String] = []
        if tokens > 0 { parts.append("\(Format.tokens(tokens)) tok") }
        if let cpu = cpuTimeMs, cpu > 0 {
            parts.append(String(format: L("CPU %@"), CapabilityResourceFormat.duration(cpu)))
        }
        if let peak = peakMemoryBytes, peak > 0 {
            parts.append(String(format: L("peak %@"), CapabilityResourceFormat.bytes(peak)))
        }
        if let duration = durationMs, duration > 0 {
            parts.append(CapabilityResourceFormat.duration(duration))
        }
        return parts
    }
}

extension ActivityEntry {
    var cliCapability: ObservedCapability? {
        capabilities?.first { $0.kind == .cli }
    }

    /// The call on one line: the tool's own prefix dropped, whitespace
    /// collapsed, the rest for when the row is opened.
    var oneLinePreview: String {
        let body = ShellCommandName.stripToolPrefix(text, tool: toolName)
        let collapsed = body.split(whereSeparator: { $0.isWhitespace || $0.isNewline }).joined(separator: " ")
        return String(collapsed.prefix(200))
    }

    /// A call that ran a shell, whether the Mac said so or only the tool's name does.
    var isShellCall: Bool {
        cliCapability != nil || ShellCommandName.isShellTool(toolName)
    }

    /// The command a shell call ran, when it can be told: "git", not "Bash".
    /// A Write is not a shell call, so its file is never mistaken for one.
    var cliCommandName: String? {
        guard isShellCall else { return nil }
        let tool = (toolName ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        // A name the Mac gave is used unless it is a shouting variable: an
        // older Mac named a cut-short preview after one.
        if let name = cliCapability?.name.trimmingCharacters(in: .whitespacesAndNewlines), !name.isEmpty,
           name.lowercased() != tool.lowercased(), !ShellCommandName.isShouting(name) {
            return name
        }
        if let named = ShellCommandName.from(cliCapability?.commandPreview) { return named }
        return ShellCommandName.from(ShellCommandName.stripToolPrefix(text, tool: tool))
    }

    /// Processor time, memory and wall time of one shell call, or nothing.
    var cliMetricsLine: String? {
        guard kind == "tool", let cli = cliCapability else { return nil }
        let parts = CliCallMetrics.parts(
            tokens: 0, cpuTimeMs: cli.resource?.effectiveCpuTimeMs,
            peakMemoryBytes: cli.resource?.effectivePeakRssBytes,
            durationMs: durationMs ?? cli.durationMs
        )
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }
}

/// What a tool row is called: "CLI · git" for the shell, "WRITE ·
/// ProjectRepositories.swift" for a file tool, so a written file never reads
/// as a command that ran.
enum ToolRowLabel {
    static func text(for entry: ActivityEntry) -> String {
        if entry.isShellCall {
            if let command = entry.cliCommandName { return "CLI · \(command)" }
            let name = entry.toolName?.trimmingCharacters(in: .whitespacesAndNewlines)
            if let name, !name.isEmpty { return "CLI · \(name)" }
            return L("CLI")
        }
        let name = (entry.toolName ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return L("TOOL") }
        if let subject = subject(of: entry) { return "\(name.uppercased()) · \(subject)" }
        return name.uppercased()
    }

    /// The file a file tool touched, by its last path component; nothing for
    /// a tool whose text is not a path.
    static func subject(of entry: ActivityEntry) -> String? {
        let body = ShellCommandName.stripToolPrefix(entry.text, tool: entry.toolName)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard let first = body.split(whereSeparator: { $0.isNewline }).first.map(String.init) else { return nil }
        let candidate = first.trimmingCharacters(in: .whitespaces)
        guard candidate.hasPrefix("/") || candidate.hasPrefix("~") || candidate.hasPrefix("./"),
              !candidate.contains(" ") else { return nil }
        let leaf = candidate.split(separator: "/").last.map(String.init) ?? candidate
        return leaf.isEmpty ? nil : String(leaf.prefix(48))
    }

    static func icon(for entry: ActivityEntry) -> String {
        if entry.isShellCall { return "terminal" }
        switch (entry.toolName ?? "").lowercased() {
        case "write", "edit", "multiedit", "notebookedit", "create_file", "edit_file", "apply_patch": return "square.and.pencil"
        case "read", "read_file", "view", "cat": return "doc.text"
        case "glob", "grep", "search", "list_dir", "codebase_search", "find": return "magnifyingglass"
        case "webfetch", "websearch", "fetch", "web_search": return "globe"
        case "task", "agent", "subagent": return "person.2"
        case "todowrite", "todoread": return "checklist"
        default: return "wrench.and.screwdriver"
        }
    }
}
