import SwiftUI
import WatchKit

struct SessionActivityView: View {
    let session: WatchSession
    @StateObject private var bridge = WatchBridge.shared
    @State private var sentReply: String?
    @State private var visibleEntries: [WatchActivityEntry] = []
    @State private var knownEntryIds = Set<String>()
    @State private var seededEntries = false

    init(session: WatchSession, initialEntries: [WatchActivityEntry] = [],
         sentReply: String? = nil) {
        self.session = session
        _sentReply = State(initialValue: sentReply)
        _visibleEntries = State(initialValue: initialEntries)
        _knownEntryIds = State(initialValue: Set(initialEntries.map(\.id)))
        _seededEntries = State(initialValue: !initialEntries.isEmpty)
    }

    private var activity: WatchActivity? {
        return bridge.state.activities.first { $0.sessionId == session.id }
    }

    private var currentState: String {
        activity?.state ?? session.state
    }

    private var stateColor: Color {
        switch currentState {
        case "working": return .green
        case "waiting": return .orange
        default: return .secondary
        }
    }

    private var stateSummary: String {
        switch currentState {
        case "working": return L("Agent is working")
        case "waiting": return L("Agent is waiting")
        default: return L("Session is idle")
        }
    }

    var body: some View {
        VStack(spacing: pt(5)) {
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: pt(6)) {
                        HStack(spacing: pt(5)) {
                            Circle()
                                .fill(stateColor)
                                .frame(width: pt(7), height: pt(7))
                            Text(stateSummary)
                                .font(.system(size: pt(11), weight: .semibold))
                                .foregroundStyle(stateColor)
                            Spacer(minLength: 0)
                            Text(session.agent.uppercased())
                                .font(.system(size: pt(9), weight: .heavy))
                                .foregroundStyle(accentFor(session.agent))
                        }

                        Text(session.title)
                            .font(.system(size: pt(14), weight: .bold))
                            .lineLimit(2)

                        usageCard

                        if !visibleEntries.isEmpty {
                            ForEach(visibleEntries) { entry in
                                VStack(alignment: .leading, spacing: pt(3)) {
                                    Text(L(entry.kind == "tool" ? "ACTION" :
                                            (entry.kind == "final" ? "FINAL" : "AGENT")))
                                        .font(.system(size: pt(9), weight: .heavy))
                                        .foregroundStyle(entry.kind == "tool" ? accentFor(session.agent) : .secondary)
                                    Text(entry.text)
                                        .font(.system(size: pt(12), design: entry.kind == "tool" ? .monospaced : .default))
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                                .padding(pt(7))
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: pt(7)))
                                .id(entry.id)
                            }
                        } else {
                            ContentUnavailableView(
                                L("No activity yet"),
                                systemImage: "ellipsis.bubble",
                                description: Text(L("The agent has not reported visible activity for this task."))
                            )
                        }

                        if let sentReply {
                            Label(String(format: L("Sent to %@"), session.agent.capitalized),
                                  systemImage: "checkmark.circle.fill")
                                .font(.system(size: pt(10), weight: .semibold))
                                .foregroundStyle(.green)
                            Text(sentReply)
                                .font(.system(size: pt(11)))
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .scrollIndicators(.visible)
                .onChange(of: visibleEntries) { _, entries in
                    guard let id = entries.last?.id else { return }
                    withAnimation(.easeOut(duration: 0.2)) {
                        proxy.scrollTo(id, anchor: .bottom)
                    }
                }
            }

            HStack(spacing: pt(5)) {
                ReplyInput(title: "Voice", icon: "mic.fill", height: pt(29),
                           fill: accentFor(session.agent), textColor: .black,
                           normalizeTechnologyTerms: true) {
                    sendReply($0)
                }
                ReplyInput(title: "Text", icon: "pencil", height: pt(29)) {
                    sendReply($0)
                }
            }
        }
        .navigationTitle(L("Activity"))
        .onAppear {
            mergeEntries(activity?.entries ?? [])
            bridge.send(.subscription(session.id, active: true, source: "detail"))
        }
        .onChange(of: activity?.entries ?? []) { _, entries in
            mergeEntries(entries)
        }
        .onDisappear {
            bridge.send(.subscription(session.id, active: false, source: "detail"))
        }
    }

    func sendReply(_ text: String) {
        sentReply = text
        bridge.send(.message(text, sessionId: session.id, agent: session.agent))
    }

    func mergeEntries(_ entries: [WatchActivityEntry]) {
        guard !entries.isEmpty else { return }
        if !seededEntries {
            knownEntryIds = Set(entries.map(\.id))
            visibleEntries = Array(entries.suffix(2))
            seededEntries = true
            return
        }

        var next = visibleEntries
        for entry in entries {
            if let index = next.firstIndex(where: { $0.id == entry.id }) {
                next[index] = entry
            } else if !knownEntryIds.contains(entry.id) {
                next.append(entry)
            }
            knownEntryIds.insert(entry.id)
        }
        next.sort { $0.createdAt < $1.createdAt }
        visibleEntries = next
    }

    @ViewBuilder
    private var usageCard: some View {
        VStack(alignment: .leading, spacing: pt(5)) {
            HStack {
                metric(L("Session tokens"), session.tokensSession)
                Spacer(minLength: pt(4))
                metric(L("Last turn"), session.tokensLastTurn)
            }

            if let used = session.contextTokensUsed,
               let window = session.contextWindow,
               window > 0 {
                Divider()
                HStack {
                    Text(L("Context"))
                        .font(.system(size: pt(10), weight: .semibold))
                    Spacer()
                    Text("\(used.formatted(.number.notation(.compactName))) / \(window.formatted(.number.notation(.compactName)))")
                        .font(.system(size: pt(11), weight: .bold, design: .rounded))
                }
                ProgressView(value: min(1, Double(used) / Double(window)))
                    .tint(accentFor(session.agent))
            } else {
                Divider()
                Text(L("Context size has not been reported yet."))
                    .font(.system(size: pt(9)))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(pt(7))
        .background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: pt(7)))
    }

    private func metric(_ label: String, _ value: Int) -> some View {
        VStack(alignment: .leading, spacing: pt(1)) {
            Text(label.uppercased())
                .font(.system(size: pt(8), weight: .heavy))
                .foregroundStyle(.secondary)
            Text(value.formatted(.number.notation(.compactName)))
                .font(.system(size: pt(12), weight: .bold, design: .rounded))
        }
    }
}
