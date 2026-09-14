import SwiftUI
import PhotosUI
import UniformTypeIdentifiers
import UIKit

struct AgentThreadTranscript: View {
    let row: ChildThreadDisplayRow
    let entries: [ActivityEntry]
    let accent: Color
    let servers: [McpServerInfo]
    /// Asked for when the card opens on nothing: the conversation is read
    /// from the computer's transcript and merged in.
    var onExpand: (() -> Void)? = nil
    @State private var expanded = false
    @State private var requestedAt: Date?
    @State private var waited = false

    init(
        row: ChildThreadDisplayRow, entries: [ActivityEntry], accent: Color,
        servers: [McpServerInfo], expanded: Bool = false, onExpand: (() -> Void)? = nil
    ) {
        self.row = row
        self.entries = entries
        self.accent = accent
        self.servers = servers
        self.onExpand = onExpand
        _expanded = State(initialValue: expanded)
    }

    private var thread: ChildThreadInfo { row.thread }

    /// Fetching, until the rows arrive or enough time has passed to say so.
    private var loading: Bool { entries.isEmpty && requestedAt != nil && !waited }

    private func fetchIfEmpty() {
        guard entries.isEmpty, requestedAt == nil else { return }
        requestedAt = Date()
        waited = false
        onExpand?()
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 8_000_000_000)
            waited = true
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                withAnimation(.easeInOut(duration: 0.18)) { expanded.toggle() }
                if expanded { fetchIfEmpty() }
            } label: {
                HStack(alignment: .top, spacing: 10) {
                    Circle()
                        .fill(thread.state == "working" ? Theme.ok : Theme.muted)
                        .frame(width: 8, height: 8)
                        .padding(.top, 6)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(row.displayLabel)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(Theme.ink)
                            .lineLimit(2)
                        HStack(spacing: 5) {
                            if let model = thread.model, !model.isEmpty {
                                Text(model)
                                Text(L("·"))
                            }
                            Text(L(thread.state))
                            Text(L("·"))
                            Text("\(Format.tokens(thread.tokensSession)) tokens")
                            if entries.count > 0 {
                                Text(L("·"))
                                Text("\(entries.count) events")
                            }
                        }
                        .font(Theme.mono(10.5))
                        .foregroundStyle(Theme.muted)
                        Text(ThreadTimeline.line(thread))
                            .font(Theme.mono(10.5))
                            .foregroundStyle(Theme.muted)
                            .accessibilityIdentifier("thread.times.\(thread.threadId)")
                        if let used = thread.contextTokensUsed {
                            Text(thread.contextWindow.map {
                                "Context \(Format.tokens(used)) / \(Format.tokens($0))"
                            } ?? "Context \(Format.tokens(used))")
                                .font(Theme.mono(10.5))
                                .foregroundStyle(Theme.muted)
                        }
                    }
                    Spacer(minLength: 8)
                    Image(systemName: "chevron.right")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(Theme.muted)
                        .rotationEffect(.degrees(expanded ? 90 : 0))
                        .padding(.top, 4)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if expanded {
                Divider().overlay(Theme.line).padding(.vertical, 10)
                if loading {
                    HStack(spacing: 8) {
                        ProgressView().controlSize(.small)
                        Text(L("Loading the conversation…"))
                    }
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.muted)
                } else if entries.isEmpty {
                    Text(L("No visible messages from this agent conversation yet."))
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.muted)
                } else {
                    VStack(alignment: .leading, spacing: 12) {
                        ForEach(entries) { entry in
                            ActivityRow(
                                entry: entry,
                                accent: accent,
                                compact: false,
                                server: entry.mcpServer.flatMap { name in
                                    servers.first { $0.name == name }
                                }
                            )
                            .id(entry.id)
                        }
                    }
                }
            }
        }
        .padding(12)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous)
            .stroke(Theme.line, lineWidth: 1))
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(L("Agent conversation")): \(row.displayLabel)")
        .onAppear { if expanded { fetchIfEmpty() } }
    }
}

/// When an agent conversation ran: "started 6 Sep 02:10 · last active 2 h ago".
enum ThreadTimeline {
    static func line(_ thread: ChildThreadInfo, now: Double = Date().timeIntervalSince1970 * 1_000) -> String {
        var parts: [String] = []
        if thread.startedAt > 0 {
            parts.append(String(format: L("started %@"), ReportBuilder.stamp(thread.startedAt)))
        }
        if thread.state == "working" {
            parts.append(L("active now"))
        } else if thread.lastActivityAt > 0 {
            let seconds = Int(max(0, (now - thread.lastActivityAt) / 1_000))
            parts.append("\(L("last active")) \(ConnectionLoadFormat.age(seconds: seconds))")
        }
        return parts.joined(separator: " · ")
    }
}
