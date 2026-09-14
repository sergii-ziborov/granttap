import SwiftUI
import WatchKit

struct ChatScreen: View {
    let chat: WatchChat

    @Environment(\.dismiss) private var dismiss
    @StateObject private var bridge = WatchBridge.shared
    @State private var step: Step
    @State private var replyText = ""
    @State private var replyByVoice = true
    @State private var decisionSubmitted = false
    @State private var decisionSubmissionStamp: Double?
    @State private var permissionFollowUpSent = false

    init(chat: WatchChat, initialStep: Step? = nil,
         initialReplyText: String = "", replyByVoice: Bool = true,
         permissionFollowUpSent: Bool = false) {
        self.chat = chat
#if DEBUG
        let resolvedStep: Step
        if let initialStep {
            resolvedStep = initialStep
        } else {
            switch ProcessInfo.processInfo.environment["GRANTTAP_STEP"] {
            case "explain": resolvedStep = .explain
            case "replied": resolvedStep = .replied
            default: resolvedStep = .ask
            }
        }
#else
        let resolvedStep: Step = initialStep ?? .ask
#endif
        _step = State(initialValue: resolvedStep)
        _replyText = State(initialValue: initialReplyText)
        _replyByVoice = State(initialValue: replyByVoice)
        _decisionSubmitted = State(initialValue: chat.waitingForMachine)
        _permissionFollowUpSent = State(initialValue: permissionFollowUpSent)
    }

    private var currentAttention: HumanAttentionItem? {
        bridge.state.humanAttention.first { $0.id == chat.id }
    }

    private var decisionWaiting: Bool {
        decisionSubmitted || currentAttention?.waitingForMachine == true
    }

    var body: some View {
        VStack(spacing: pt(5)) {
            header

            // Crown territory: only the text scrolls…
            ScrollView {
                VStack(alignment: .leading, spacing: pt(7)) {
                    scrollContent
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.bottom, pt(4))
            }

            // …while the buttons live here and never move.
            pinnedButtons
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .padding(.horizontal, pt(4))
        .onChange(of: currentAttention?.waitingForMachine) { _, waiting in
            if waiting == false, currentAttention != nil, decisionSubmissionStamp == nil {
                decisionSubmitted = false
            }
        }
        .onChange(of: bridge.state.stamp) { _, stamp in
            guard let submittedAt = decisionSubmissionStamp,
                  stamp != submittedAt,
                  currentAttention != nil,
                  currentAttention?.waitingForMachine != true else { return }
            // The phone processed the tap but could not deliver it. Its newer
            // snapshot is authoritative and re-enables the buttons.
            decisionSubmitted = false
            decisionSubmissionStamp = nil
        }
        .onChange(of: bridge.state.humanAttention.contains(where: { $0.id == chat.id })) { _, present in
            if chat.attentionAction != nil, !present { dismiss() }
        }
    }

    private var header: some View {
        HStack(alignment: .top, spacing: pt(5)) {
            VStack(alignment: .leading, spacing: pt(2)) {
                Text(chat.ask)
                    .font(.system(size: pt(13), weight: .bold))
                    .lineLimit(2)
                Text(chat.agent)
                    .font(.system(size: pt(9), weight: .semibold))
                    .foregroundStyle(chat.accent)
            }
            Spacer(minLength: pt(2))
            if chat.attentionAction == .decision && !decisionWaiting
                && WatchAction.canSendPermissionFollowUp(sessionId: chat.sessionId) {
                ReplyInput(title: "Reply", icon: "quote.bubble", height: pt(24),
                           fill: chat.accent, textColor: .black,
                           normalizeTechnologyTerms: true) {
                    reply(voice: true, text: $0)
                }
            }
        }
    }

    // MARK: scrolling content

    @ViewBuilder
    private var scrollContent: some View {
        switch step {
        case .ask:
            if let risk = chat.risk,
               !["safe", "low"].contains(risk.lowercased()) {
                  Text("\(L("RISK")): \(L(risk).uppercased())")
                    .font(.system(size: pt(10), weight: .heavy))
                    .foregroundStyle(.black)
                    .padding(.horizontal, pt(7)).padding(.vertical, pt(3))
                    .background(denyRed, in: Capsule())
            }
            if let cmd = chat.cmd {
                Text("$ " + cmd)
                    .font(.system(size: pt(11), design: .monospaced))
                    .lineLimit(2)
                    .truncationMode(.tail)
                    .padding(.horizontal, pt(7)).padding(.vertical, pt(5))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(.white.opacity(0.09), in: RoundedRectangle(cornerRadius: pt(7)))
            }
            if chat.isPermission && permissionFollowUpSent && !decisionWaiting {
                Label(L("Message sent · decision still needed"),
                      systemImage: "checkmark.bubble.fill")
                    .font(.system(size: pt(10), weight: .semibold))
                    .foregroundStyle(.green)
                    .fixedSize(horizontal: false, vertical: true)
            }

        case .explain:
              Label(L("Denied"), systemImage: "xmark.circle.fill")
                .font(.system(size: pt(11), weight: .semibold))
                .foregroundStyle(denyRed)
              Text(L("Say what to do instead?"))
                .font(.system(size: pt(15), weight: .semibold))
                .fixedSize(horizontal: false, vertical: true)

        case .replied:
              Text(replyByVoice ? L("YOU · VOICE") : L("YOU"))
                .font(.system(size: pt(9), weight: .heavy))
                .foregroundStyle(.secondary)
            Text(replyText)
                .font(.system(size: pt(15), weight: .semibold))
                .fixedSize(horizontal: false, vertical: true)
              Label(String(format: L("Sent to %@"), chat.agent), systemImage: "checkmark.circle.fill")
                .font(.system(size: pt(11), weight: .semibold))
                .foregroundStyle(.green)
        }
    }

    // MARK: pinned buttons
    //
    // Hand-rolled capsules: watchOS system buttons keep their full tap-target
    // height even at .controlSize(.small), and two such rows push the question
    // itself off a 42mm screen.

    @ViewBuilder
    private var pinnedButtons: some View {
        switch step {
        case .ask where chat.attentionAction == .openPhone
            || chat.attentionAction == .retryOnPhone:
            Label(L("Open GrantTap on iPhone"), systemImage: "iphone")
                .font(.system(size: pt(11), weight: .semibold))
                .foregroundStyle(.secondary)

        case .ask where chat.isPermission:
            // Voice and text are pinned in the header for permission cards, so
            // the command and playback control keep the full Crown scroll area.
            if decisionWaiting {
                HStack(spacing: pt(6)) {
                    ProgressView()
                    Text(L("Decision sent · waiting for Mac…"))
                        .font(.system(size: pt(10), weight: .semibold))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            } else {
                HStack(spacing: pt(5)) {
                    Pill(title: "Deny", icon: "xmark", height: pt(36),
                         fill: denyRed.opacity(0.22), textColor: denyRed) { onDeny() }
                    Pill(title: "Allow", icon: "checkmark", height: pt(36),
                         fill: chat.accent, textColor: .black) { onApprove() }
                }
            }

        case .ask: // open question — voice IS the answer
            replyInputs

        case .explain:
            replyInputs

        case .replied:
            Pill(title: "Again", height: pt(32)) { step = .ask }
        }
    }

    /// Native watchOS input. TextFieldLink opens the system text controller,
    /// including Dictation, instead of simulating a canned voice response.
    private var replyInputs: some View {
        ReplyInput(title: "Reply", icon: "quote.bubble", height: pt(30),
                   fill: chat.accent, textColor: .black,
                   normalizeTechnologyTerms: true) {
            reply(voice: true, text: $0)
        }
    }

    // MARK: bits

    /// Send the real decision through the paired phone. Only the phone's next
    /// machine-confirmed snapshot may call it resolved.
    func onApprove() {
        decisionSubmissionStamp = bridge.state.stamp
        let action = chat.attentionAction == .meshDecision
            ? WatchAction.meshDecision(chat.id, allow: true)
            : WatchAction.decision(chat.id, "allow", sessionId: chat.sessionId)
        WatchBridge.shared.send(action)
        decisionSubmitted = true
    }

    /// Deny remains pending until the machine confirms the native gate closed.
    func onDeny() {
        decisionSubmissionStamp = bridge.state.stamp
        let action = chat.attentionAction == .meshDecision
            ? WatchAction.meshDecision(chat.id, allow: false)
            : WatchAction.decision(chat.id, "deny", sessionId: chat.sessionId)
        WatchBridge.shared.send(action)
        decisionSubmitted = true
    }

    func reply(voice: Bool, text: String) {
        replyByVoice = voice
        replyText = text
        if chat.attentionAction == .meshReply {
            WatchBridge.shared.send(.meshAnswer(text, eventId: chat.id))
            step = .replied
            return
        }
        if chat.attentionAction == .openPhone || chat.attentionAction == .retryOnPhone {
            return
        }
        if chat.isPermission {
            guard let action = WatchAction.permissionFollowUp(
                text,
                sessionId: chat.sessionId,
                agent: chat.agent
            ) else { return }
            WatchBridge.shared.send(action)
            // Guidance does not answer the permission. Keep Allow/Deny visible
            // until the phone mirrors a machine-confirmed resolution.
            permissionFollowUpSent = true
            return
        }
        if let requestId = chat.requestId {
            WatchBridge.shared.send(.questionReply(
                text,
                sessionId: chat.sessionId,
                requestId: requestId
            ))
        } else {
            WatchBridge.shared.send(.message(
                text,
                sessionId: chat.sessionId,
                agent: AgentIdentity.normalize(chat.agent)
            ))
        }
        step = .replied
    }

}

// MARK: - compact capsule button
