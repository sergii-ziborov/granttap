import SwiftUI
import WatchKit

struct NewVoiceTaskView: View {
    @StateObject private var bridge = WatchBridge.shared
    @State private var agent: String
    @State private var sentText: String?

    init(initialAgent: String = "codex", sentText: String? = nil) {
        let normalized = AgentIdentity.normalize(initialAgent)
        _agent = State(
            initialValue: watchNewTaskAgentIds.contains(normalized) ? normalized : "codex"
        )
        _sentText = State(initialValue: sentText)
    }

    var body: some View {
        List {
            Section(L("Agent")) {
                Picker(L("Agent"), selection: $agent) {
                    ForEach(watchNewTaskAgentIds, id: \.self) { id in
                        Text(AgentIdentity.displayName(id)).tag(id)
                    }
                }
            }

            Section(L("Instruction")) {
                ReplyInput(
                    title: "Speak task",
                    icon: "mic.fill",
                    height: pt(38),
                    fill: accentFor(agent),
                    textColor: .black,
                    prompt: "Describe a new task",
                    normalizeTechnologyTerms: true
                ) { text in
                    bridge.send(.newTask(text, agent: agent))
                    sentText = text
                }
                Text(L("Dictation is converted to text on Apple Watch and sent through the paired iPhone."))
                    .font(.system(size: pt(9)))
                    .foregroundStyle(.secondary)
            }

            if let sentText {
                Section(L("Sent")) {
                    Label(
                        String(format: L("New task sent to %@"), AgentIdentity.displayName(agent)),
                        systemImage: "checkmark.circle.fill"
                    )
                    .foregroundStyle(.green)
                    Text(sentText)
                        .font(.system(size: pt(10)))
                        .foregroundStyle(.secondary)
                }
            }
        }
        .navigationTitle(L("New task"))
    }
}

// MARK: - swipe-up: every session at a glance
