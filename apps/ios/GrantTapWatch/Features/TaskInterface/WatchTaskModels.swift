import SwiftUI
import WatchKit

// Wrist rules (v3, per user feedback):
//   • the Digital Crown scrolls the TEXT of the current chat; the buttons are
//     pinned below the scroll area and never move
//   • horizontal swipe switches between chats (page dots off — the sessions
//     sheet is the overview)
//   • swipe up shows all sessions as a list
//   • speech only on demand
//   • screens follow the HTML prototype: labelled Отклонить/Разрешить, then
//     Нет/Да + «или ответить», voice/text as the way to TALK to the agent —
//     and after a deny you get voice/text to say what to do instead

enum Step { case ask, explain, replied }

struct WatchChat: Identifiable {
    let id: String
    let agent: String
    let accent: Color
    let risk: String?          // nil → not a permission request
    let ask: String
    let cmd: String?
    let isPermission: Bool
    var attentionAction: HumanAttentionAction? = nil
    var sessionId: String? = nil
    var requestId: String? = nil
    var waitingForMachine = false
}

func accentFor(_ agent: String) -> Color {
    switch AgentIdentity.normalize(agent) {
    case "codex":
        return .white
    case "cursor":
        return Color(red: 0.18, green: 0.83, blue: 0.75)
    case "grok":
        return Color(red: 0.82, green: 0.55, blue: 1.0)
    case "claude":
        return Color(red: 0.93, green: 0.42, blue: 0.24)
    default:
        return Color(red: 0.93, green: 0.42, blue: 0.24)
    }
}

func glyphInkFor(_ agent: String) -> Color {
    .black
}

func agentGlyph(_ agent: String) -> String {
    AgentIdentity.glyph(agent)
}

/** Headless new-task launch exists only for these providers today. */
let watchNewTaskAgentIds = ["claude", "codex", "grok"]

extension WatchChat {
    /// A real permission request mirrored from the phone.
    init(from a: WatchApproval) {
        self.init(
            id: a.id,
            agent: AgentIdentity.displayName(a.agent),
            accent: accentFor(a.agent),
            risk: a.risk == "low" ? nil : (a.risk == "high" ? "high" : "medium"),
            ask: a.title,
            cmd: a.command,
            isPermission: true,
            attentionAction: .decision,
            sessionId: a.sessionId,
            requestId: a.id,
            waitingForMachine: a.waitingForMachine == true
        )
    }

    init(from q: WatchQuestion) {
        self.init(
            id: q.id,
            agent: "GrantTap",
            accent: accentFor("claude"),
            risk: nil,
            ask: q.text,
            cmd: nil,
            isPermission: false,
            attentionAction: .reply,
            sessionId: q.sessionId,
            requestId: q.id
        )
    }

    init(from item: HumanAttentionItem) {
        let agent = attentionAgentName(item.agent)
        self.init(
            id: item.id,
            agent: agent,
            accent: accentFor(item.agent ?? "claude"),
            risk: item.risk,
            ask: item.title,
            cmd: item.command ?? item.detail,
            isPermission: [.decision, .meshDecision].contains(item.action),
            attentionAction: item.action,
            sessionId: item.sessionId,
            requestId: item.id,
            waitingForMachine: item.waitingForMachine == true
        )
    }

    /// Nothing waiting — offer to talk to the most recent session.
    static func idle(_ state: WatchState) -> WatchChat {
        let s = state.sessions.first
        return WatchChat(
            id: "idle",
            agent: s.map { AgentIdentity.displayName($0.agent) } ?? "GrantTap",
            accent: accentFor(s?.agent ?? "claude"),
            risk: nil,
            ask: s.map { "\($0.title) — \(stateWord($0.state))" } ?? L("Nothing is waiting."),
            cmd: nil,
            isPermission: false,
            sessionId: s?.id
        )
    }
}

func attentionAgentName(_ agent: String?) -> String {
    guard let agent else { return "GrantTap" }
    return agent == "grok_bot" ? "Grok Bot" : AgentIdentity.displayName(agent)
}

func stateWord(_ s: String) -> String {
    switch s { case "working": return L("working"); case "waiting": return L("waiting"); default: return L("idle") }
}

let denyRed = Color(red: 1, green: 0.42, blue: 0.32)

/// 45mm is the reference; clamp so 41/42mm doesn't clip and 49mm isn't tiny.
var uiScale: CGFloat {
    let w = WKInterfaceDevice.current().screenBounds.width
    return max(0.86, min(1.10, w / 198))
}
func pt(_ base: CGFloat) -> CGFloat { (base * uiScale).rounded() }

/// Compact brand mark for small watchOS navigation chrome.
struct WatchBrandMark: View {
    var size: CGFloat
    var cornerRadius: CGFloat? = nil

    var body: some View {
        Image("BrandMark")
            .resizable()
            .scaledToFit()
            .frame(width: size, height: size)
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius ?? size * 0.22))
            .accessibilityLabel("GrantTap")
    }
}

// MARK: - root: one unified task list, colored by agent
