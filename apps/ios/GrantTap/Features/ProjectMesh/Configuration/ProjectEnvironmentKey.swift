import Foundation

enum ProjectEnvironmentKey {
    private static let protectedNames: Set<String> = [
        "HOME", "PATH", "SHELL", "USER", "LOGNAME", "TMPDIR", "NODE_OPTIONS"
    ]
    private static let protectedPrefixes = [
        "GRANTTAP_", "NODVOX_", "XDG_", "DYLD_", "LD_", "OPENAI_",
        "ANTHROPIC_", "CODEX_", "CLAUDE_", "CURSOR_", "GROK_"
    ]

    static func allowed(_ key: String) -> Bool {
        guard key.range(of: "^[A-Z][A-Z0-9_]{0,127}$", options: .regularExpression) != nil,
              !protectedNames.contains(key) else { return false }
        return !protectedPrefixes.contains { key.hasPrefix($0) }
    }
}
