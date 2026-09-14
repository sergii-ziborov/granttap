import SwiftUI

/// A folded run of tool calls: one sentence in the chat, the steps behind it
/// in a sheet, each step opening to what it touched and what it changed.
struct ActivityRunRow: View {
    let run: ChatActivityRun
    let accent: Color
    /// A focused entry inside the run opens it: a history tap must land on the
    /// call it named, not on a closed summary of it.
    var forceOpen: Bool = false
    var highlightedEntryId: String? = nil
    var serverFor: (ActivityEntry) -> McpServerInfo? = { _ in nil }
    @State private var showSteps: Bool

    init(
        run: ChatActivityRun, accent: Color, forceOpen: Bool = false,
        highlightedEntryId: String? = nil,
        serverFor: @escaping (ActivityEntry) -> McpServerInfo? = { _ in nil }
    ) {
        self.run = run
        self.accent = accent
        self.forceOpen = forceOpen
        self.highlightedEntryId = highlightedEntryId
        self.serverFor = serverFor
        _showSteps = State(initialValue: forceOpen)
    }

    var body: some View {
        Button {
            showSteps = true
        } label: {
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: "list.bullet.rectangle.portrait")
                    .foregroundStyle(accent)
                    .frame(width: 18)
                VStack(alignment: .leading, spacing: 3) {
                    Text(run.sentence)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Theme.ink)
                        .multilineTextAlignment(.leading)
                        .lineLimit(2)
                    HStack(spacing: 6) {
                        Text([LPlural(run.calls, one: "%d step", many: "%d steps"), run.metricsLine]
                            .compactMap { $0 }.joined(separator: " · "))
                        if run.failures > 0 {
                            Text(String(format: L("%d failed"), run.failures)).foregroundStyle(Theme.riskHigh)
                        }
                    }
                    .font(.system(size: 10.5))
                    .foregroundStyle(Theme.muted)
                    .lineLimit(1)
                }
                Spacer(minLength: 4)
                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(Theme.muted)
                    .padding(.top, 3)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("chat.run.\(run.id)")
        .padding(.vertical, 2)
        .sheet(isPresented: $showSteps) {
            ActivityRunSheet(run: run, accent: accent, highlightedEntryId: highlightedEntryId, serverFor: serverFor)
        }
    }
}

/// The steps of a run, in order, on a timeline.
struct ActivityRunSheet: View {
    let run: ChatActivityRun
    let accent: Color
    var highlightedEntryId: String? = nil
    var serverFor: (ActivityEntry) -> McpServerInfo? = { _ in nil }
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        CompatNavigationStack {
            List {
                Section {
                    ForEach(Array(run.steps.enumerated()), id: \.element.id) { index, step in
                        NavigationLink {
                            ActivityStepDetail(step: step, accent: accent, server: serverFor(step.entry))
                        } label: {
                            ActivityStepRow(step: step, isLast: index == run.steps.count - 1,
                                            highlighted: step.id == highlightedEntryId)
                        }
                        .listRowSeparator(.hidden)
                        .listRowInsets(EdgeInsets(top: 0, leading: 16, bottom: 0, trailing: 16))
                        .accessibilityIdentifier("run.step.\(step.id)")
                    }
                } footer: {
                    if let metrics = run.metricsLine {
                        Text(metrics).font(.caption).foregroundStyle(Theme.muted).padding(.top, 8)
                    }
                }
            }
            .listStyle(.plain)
            .navigationTitle(run.sentence)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button { dismiss() } label: { Image(systemName: "xmark") }
                        .accessibilityLabel(L("Close"))
                }
            }
        }
    }
}

/// One step on the timeline: the verb, what it touched, and how much changed.
struct ActivityStepRow: View {
    let step: ActivityStep
    var isLast: Bool = false
    var highlighted: Bool = false

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(spacing: 0) {
                Image(systemName: step.icon)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(step.failed ? Theme.riskHigh : Theme.muted)
                    .frame(width: 30, height: 30)
                    .background(Circle().fill(Theme.raised))
                    .overlay(Circle().stroke(Theme.line, lineWidth: 1))
                if !isLast {
                    Rectangle().fill(Theme.line).frame(width: 1).frame(minHeight: 18)
                }
            }
            VStack(alignment: .leading, spacing: 3) {
                Text(step.title)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(Theme.ink)
                if let subject = step.subject, !subject.isEmpty {
                    Text(subject)
                        .font(.system(size: 13))
                        .foregroundStyle(Theme.muted)
                        .lineLimit(2)
                }
                if step.failed {
                    Text(L("Failed")).font(.caption2.weight(.bold)).foregroundStyle(Theme.riskHigh)
                }
            }
            .padding(.top, 5)
            .padding(.bottom, 14)
            Spacer(minLength: 8)
            if let stats = step.entry.diffStats {
                DiffStatsBadge(added: stats.added, removed: stats.removed).padding(.top, 9)
            }
        }
        .background(highlighted ? Theme.riskMed.opacity(0.12) : .clear)
    }
}

/// One call in full: what it touched, what it was for, what it changed.
struct ActivityStepDetail: View {
    let step: ActivityStep
    let accent: Color
    var server: McpServerInfo? = nil

    private var entry: ActivityEntry { step.entry }
    private var body_: String { ShellCommandName.stripToolPrefix(entry.text, tool: entry.toolName) }

    var body: some View {
        List {
            Section {
                Text(body_.isEmpty ? entry.text : body_)
                    .font(Theme.mono(12.5))
                    .foregroundStyle(Theme.ink)
                    .textSelection(.enabled)
            } header: {
                Text(subjectHeader)
            }
            if let summary = entry.summary, !summary.isEmpty {
                Section(L("Description")) {
                    Text(summary).font(.system(size: 14)).foregroundStyle(Theme.ink)
                }
            }
            if let preview = entry.diffPreview, !preview.isEmpty {
                Section {
                    DiffPreviewView(text: preview)
                        .listRowInsets(EdgeInsets(top: 8, leading: 12, bottom: 8, trailing: 12))
                } header: {
                    HStack {
                        Text(L("Content"))
                        Spacer()
                        if let stats = entry.diffStats { DiffStatsBadge(added: stats.added, removed: stats.removed) }
                    }
                }
            }
            Section(L("Result")) {
                CompatLabeledContent(L("Outcome"), value: step.failed ? L("Failed") : L("OK"))
                if let errorClass = entry.errorClass, !errorClass.isEmpty {
                    CompatLabeledContent(L("Error"), value: errorClass)
                }
                if let metrics = entry.cliMetricsLine ?? tokensLine {
                    CompatLabeledContent(L("Cost"), value: metrics)
                }
                CompatLabeledContent(L("When"), value: ReportBuilder.stamp(entry.createdAt))
                if let server {
                    CompatLabeledContent(L("MCP server"), value: server.displayTitle)
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle(step.kind == .used ? step.usedName : (entry.toolName ?? step.title))
        .navigationBarTitleDisplayMode(.inline)
    }

    private var subjectHeader: String {
        switch step.kind {
        case .created, .edited, .read: return L("File")
        case .ran: return L("Command")
        case .searched, .fetched: return L("Query")
        case .delegated: return L("Task")
        case .used: return L("Call")
        }
    }

    private var tokensLine: String? {
        guard let tokens = entry.estimatedContextTokens, tokens > 0 else { return nil }
        return "\(Format.tokens(tokens)) tok"
    }
}
