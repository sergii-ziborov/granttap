import SwiftUI
import PhotosUI
import UniformTypeIdentifiers
import UIKit

struct InChatApprovalsBar: View {
    @EnvironmentObject private var model: AppModel
    var sessionId: String? = nil
    let onReply: (String) -> Void

    private var chatPending: [ApprovalRequest] {
        let all = model.pending
        guard let sessionId else { return Array(all.prefix(2)) }
        let resolved = model.resolvedSessionId(sessionId)
        let matched = all.filter { req in
            guard let sid = req.sessionId?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !sid.isEmpty else { return false }
            return model.resolvedSessionId(sid) == resolved || sid == sessionId
        }
        if !matched.isEmpty { return Array(matched.prefix(2)) }
        // Unscoped legacy cards still surface so the user can answer.
        return Array(all.filter { ($0.sessionId ?? "").isEmpty }.prefix(2))
    }

    private var chatQuestions: [AgentEvent] {
        let all = model.questions
        guard let sessionId else { return Array(all.prefix(1)) }
        let resolved = model.resolvedSessionId(sessionId)
        let matched = all.filter { q in
            guard let sid = q.sessionId?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !sid.isEmpty else { return false }
            return model.resolvedSessionId(sid) == resolved || sid == sessionId
        }
        if !matched.isEmpty { return Array(matched.prefix(1)) }
        return Array(all.filter { ($0.sessionId ?? "").isEmpty }.prefix(1))
    }

    private var hasItems: Bool { !chatPending.isEmpty || !chatQuestions.isEmpty }

    var body: some View {
        if hasItems {
            VStack(alignment: .leading, spacing: 6) {
                Text(L("Needs You"))
                    .font(.system(size: 10, weight: .heavy))
                    .tracking(0.6)
                    .foregroundStyle(Theme.riskMed)
                ForEach(chatPending) { req in
                    compactApproval(req)
                }
                ForEach(chatQuestions, id: \.requestId) { question in
                    compactQuestion(question)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .frame(maxWidth: .infinity, maxHeight: 130, alignment: .top)
            .clipped()
            .background(Theme.riskMed.opacity(0.12))
            .overlay(Rectangle().fill(Theme.riskMed.opacity(0.55)).frame(height: 2), alignment: .top)
        }
    }

    @ViewBuilder
    private func compactApproval(_ req: ApprovalRequest) -> some View {
        if model.isMcpAskApproval(req) {
            HStack(alignment: .center, spacing: 8) {
                Text(req.title)
                    .font(.system(size: 12.5, weight: .semibold))
                    .foregroundStyle(Theme.ink)
                    .lineLimit(2)
                    .frame(maxWidth: .infinity, alignment: .leading)
                if model.approvalDecisionsInFlight[req.requestId] != nil {
                    ProgressView()
                    Text(L("Waiting for Mac…"))
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Theme.muted)
                } else {
                    if model.isMcpOpenAsk(req) {
                        compactChip(L("Reply"), tint: Theme.codex, filled: true,
                                    textColor: Theme.glyphInk(for: "codex")) {
                            onReply(req.requestId)
                        }
                    } else {
                        compactChip("No", tint: Theme.riskHigh, filled: false) {
                            model.answerQuestion(req.requestId, "no")
                        }
                        compactChip("Yes", tint: Theme.ok, filled: true) {
                            model.answerQuestion(req.requestId, "yes")
                        }
                    }
                }
            }
            .padding(8)
            .background(Theme.raised, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        } else {
            HStack(alignment: .center, spacing: 8) {
                AgentGlyph(agent: req.agent, size: 22)
                VStack(alignment: .leading, spacing: 2) {
                    Text(req.title)
                        .font(.system(size: 12.5, weight: .semibold))
                        .foregroundStyle(Theme.ink)
                        .lineLimit(2)
                    if let command = req.command, !command.isEmpty {
                        Text(command)
                            .font(Theme.mono(10.5))
                            .foregroundStyle(Theme.muted)
                            .lineLimit(1)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                if model.approvalDecisionsInFlight[req.requestId] != nil {
                    ProgressView()
                    Text(L("Waiting for Mac…"))
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Theme.muted)
                } else {
                    compactChip(L("Deny"), tint: Theme.riskHigh, filled: false) {
                        model.decide(req, "deny")
                    }
                    compactChip(L("Allow"), tint: Theme.accent(for: req.agent), filled: true,
                                textColor: Theme.glyphInk(for: req.agent)) {
                        model.decide(req, "allow")
                    }
                }
            }
            .padding(8)
            .background(Theme.raised, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
    }

    private func compactQuestion(_ question: AgentEvent) -> some View {
        HStack(alignment: .center, spacing: 8) {
            Text(question.text)
                .font(.system(size: 12.5, weight: .semibold))
                .foregroundStyle(Theme.ink)
                .lineLimit(2)
                .frame(maxWidth: .infinity, alignment: .leading)
            if let id = question.requestId,
               model.approvalDecisionsInFlight[id] != nil {
                ProgressView()
                Text(L("Waiting for Mac…"))
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Theme.muted)
            } else {
                compactChip(L("Reply"), tint: Theme.codex, filled: true,
                            textColor: Theme.glyphInk(for: "codex")) {
                    if let id = question.requestId { onReply(id) }
                }
            }
        }
        .padding(8)
        .background(Theme.raised, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    /// Intrinsic-width chips — never `FilledButton`/`OutlineButton` (those are `maxWidth: .infinity`).
    private func compactChip(_ title: String, tint: Color, filled: Bool,
                             textColor: Color = .white,
                             action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(filled ? textColor : tint)
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .background(filled ? tint : Theme.raised, in: Capsule())
                .overlay(Capsule().stroke(filled ? Color.clear : tint.opacity(0.45), lineWidth: 1.2))
        }
        .buttonStyle(.plain)
        .fixedSize()
    }
}

// MARK: - approval card
