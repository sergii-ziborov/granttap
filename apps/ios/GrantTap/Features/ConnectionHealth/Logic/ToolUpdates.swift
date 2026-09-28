import SwiftUI

/// A coding agent's command-line tool, kept current from the phone.
///
/// A tool that lags the rest of the environment fails in ways the phone can
/// only report — a chat the desktop app wrote that an older Claude Code cannot
/// resume. The phone may ask for the fix, but it chooses only which tool: the
/// command is the computer's, fixed by how that tool was installed, and the
/// computer never downloads a tool itself.
enum ToolUpdateProgress: Equatable {
    case running(requestId: String, startedAt: Double)
    case finished(ToolUpdateResult)
}

enum ToolCatalog {
    static func name(_ agent: String) -> String {
        switch agent {
        case "claude": return "Claude Code"
        case "codex": return "Codex CLI"
        case "cursor": return "Cursor CLI"
        case "grok": return "Grok CLI"
        default: return agent
        }
    }
}

extension AppModel {
    static func toolUpdateKey(room: String, agent: String) -> String { "\(room)\u{1f}\(agent)" }

    func toolUpdate(room: String, agent: String) -> ToolUpdateProgress? {
        toolUpdates[Self.toolUpdateKey(room: room, agent: agent)]
    }

    /// Ask one computer to run a tool's own updater. Returns the request id,
    /// or nothing when that computer has no link to carry the request.
    @discardableResult
    func updateTool(agent: String, room: String, send: ((ToolUpdate) -> Void)? = nil) -> String? {
        let payload = ToolUpdate(
            type: "tool.update", agent: agent, requestId: UUID().uuidString,
            createdAt: Date().timeIntervalSince1970 * 1000
        )
        if let send {
            send(payload)
        } else if let relay = relaysByRoom[room] {
            relay.updateTool(payload)
        } else {
            return nil
        }
        toolUpdates[Self.toolUpdateKey(room: room, agent: agent)] =
            .running(requestId: payload.requestId, startedAt: payload.createdAt)
        return payload.requestId
    }

    func receive(_ result: ToolUpdateResult, fromRoom room: String) {
        toolUpdates[Self.toolUpdateKey(room: room, agent: result.agent)] = .finished(result)
        append(result.message)
    }
}

/// One tool on one computer: what version answers, and the one button that
/// brings it up to date.
struct ToolVersionRow: View {
    let info: AgentIntegrationInfo
    let progress: ToolUpdateProgress?
    let computerName: String
    var onUpdate: () -> Void
    @State private var confirming = false

    var isRunning: Bool {
        if case .running = progress { return true }
        return info.updating == true
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                Text(ToolCatalog.name(info.agent)).font(.system(size: 15, weight: .semibold))
                if let version = info.version {
                    Text(version).font(Theme.mono(13, .regular)).foregroundStyle(Theme.muted)
                }
                Spacer()
                if isRunning {
                    ProgressView().controlSize(.small)
                } else if info.updateCommand != nil {
                    Button(L("Update")) { confirming = true }
                        .buttonStyle(.borderless)
                        .font(.system(size: 13, weight: .semibold))
                }
            }
            Text(subtitle).font(.caption).foregroundStyle(Theme.muted)
            if case .finished(let result) = progress {
                Text(result.message)
                    .font(.caption)
                    .foregroundStyle(result.ok ? Theme.ok : Theme.riskHigh)
                if let output = result.output, !output.isEmpty {
                    DisclosureGroup(L("Output")) {
                        Text(output).font(Theme.mono(11, .regular)).foregroundStyle(Theme.muted)
                    }
                    .font(.caption)
                }
            }
        }
        .padding(.vertical, 2)
        .alert(
            String(format: L("Update %@ on %@?"), ToolCatalog.name(info.agent), computerName),
            isPresented: $confirming
        ) {
            Button(L("Update")) { onUpdate() }
            Button(L("Cancel"), role: .cancel) {}
        } message: {
            Text(String(format: L("GrantTap will run %@ on that computer and report the result here."),
                        info.updateCommand ?? ""))
        }
    }

    var subtitle: String {
        if isRunning { return L("Updating…") }
        if let newer = info.newerOnThisMac {
            return String(format: L("A newer copy (%@) is already on this computer and answers GrantTap. Update brings the command line up to it."), newer)
        }
        if !info.installed { return L("Not installed.") }
        if let command = info.updateCommand { return command }
        return L("Kept current outside GrantTap.")
    }
}
