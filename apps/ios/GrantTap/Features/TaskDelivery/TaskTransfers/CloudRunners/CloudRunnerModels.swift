import Foundation

/// A provider cloud run a computer started for a Task. GrantTap holds only its
/// link: it cannot follow the run's progress, state or usage.
struct ExternalExecution: Codable, Equatable {
    let runner: String
    var url: String? = nil

    var provider: String { runner == "codex_cloud" ? "codex" : "claude" }

    /// Only an https link the computer reported; anything else is not opened.
    var link: URL? {
        guard let url, url.hasPrefix("https://"), let value = URL(string: url), value.host != nil else { return nil }
        return value
    }

    func title(computer: String) -> String {
        String(format: provider == "codex" ? L("Codex Cloud · via %@") : L("Claude cloud · via %@"), computer)
    }
}

/// Asks the computer that holds the Task to start a cloud run instead of a chat.
struct ProjectMeshCloudLaunch: Codable, Equatable {
    var environment: String? = nil
    var effort: String? = nil
}

/// A Transfer-to destination that is a provider's cloud runner, started by the
/// computer behind `room` with its own CLI.
struct TaskHandoffCloudTarget: Equatable {
    static let providers = ["claude", "codex"]
    private static let separator: Character = "\u{1f}"

    let provider: String
    let room: String

    init(provider: String, room: String) {
        self.provider = provider
        self.room = room
    }

    /// The picker tag; a computer's own room never looks like one.
    init?(tag: String) {
        let parts = tag.split(separator: Self.separator, maxSplits: 2, omittingEmptySubsequences: false)
        guard parts.count == 3, parts[0] == "cloud", Self.providers.contains(String(parts[1])), !parts[2].isEmpty
        else { return nil }
        self.init(provider: String(parts[1]), room: String(parts[2]))
    }

    var tag: String { ["cloud", provider, room].joined(separator: String(Self.separator)) }

    func label(computer: String) -> String {
        ExternalExecution(runner: provider == "codex" ? "codex_cloud" : "claude_cloud").title(computer: computer)
    }

    /// Runners the computer says its installed CLI can start without a terminal.
    static func available(in integrations: [AgentIntegrationInfo]) -> [String] {
        providers.filter { provider in
            integrations.contains { $0.agent == provider && $0.installed && $0.cloud == true }
        }
    }

    /// Ready, but the cloud runner only sees what the remote already has.
    static func readiness(push: Bool) -> HandoffReadinessCheck {
        HandoffReadinessCheck(
            id: "cloudBranch", title: L("Remote branch"), ready: true,
            detail: push
                ? L("The computer pushes the branch before the cloud run starts.")
                : L("The cloud runner fetches the branch from the remote. Turn on pushing unless it is already pushed."),
            warning: !push
        )
    }
}
