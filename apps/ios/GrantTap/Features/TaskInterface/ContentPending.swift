import SwiftUI
import PhotosUI
import UniformTypeIdentifiers
import UIKit

extension ContentView {
    var actionRequests: [ActionRequest] {
        let approvals = model.pending.map { request in
            ActionRequest(
                id: request.requestId, sessionId: request.sessionId, agent: request.agent,
                kind: model.isMcpAskApproval(request) ? .yesNo : .permission,
                title: request.title, detail: request.cwd, command: request.command,
                risk: actionRisk(request),
                state: model.approvalDecisionsInFlight[request.requestId] == nil
                    ? .pending : .submitting,
                createdAt: request.createdAt
            )
        }
        let questions = model.questions.map { question in
            ActionRequest(id: question.requestId ?? "question:\(question.createdAt)",
                          sessionId: question.sessionId, agent: nil, kind: .question,
                          title: question.text, risk: .safe, state: .pending,
                          createdAt: question.createdAt)
        }
        let retries = failedDeliveries.map { delivery in
            ActionRequest(id: "delivery:\(delivery.id)", sessionId: delivery.sessionId,
                          agent: delivery.agent, kind: .deliveryRetry,
                          title: L("Delivery failed"), detail: delivery.error,
                          risk: .caution, state: .failed, createdAt: delivery.createdAt)
        }
        return (approvals + questions + retries).sorted { $0.createdAt > $1.createdAt }
    }

    var failedDeliveries: [OutgoingDelivery] {
        model.deliveries.filter { $0.state == .failed && $0.admissionRejected != true }
    }

    func actionRisk(_ request: ApprovalRequest) -> ActionRequestRisk {
        switch request.danger {
        case .destructive: return .destructive
        case .dangerous: return .dangerous
        case .caution: return .caution
        case .safe: return .safe
        case nil: return request.risk == .high ? .dangerous
            : (request.risk == .medium ? .caution : .safe)
        }
    }

    var orderedPending: [ApprovalRequest] {
        guard let focus = model.focusedApprovalId else { return model.pending }
        return model.pending.sorted {
            ($0.requestId == focus ? 0 : 1) < ($1.requestId == focus ? 0 : 1)
        }
    }

    func focusedRing(_ requestId: String) -> some View {
        RoundedRectangle(cornerRadius: Theme.radius, style: .continuous)
            .stroke(model.focusedApprovalId == requestId ? Theme.claude : .clear, lineWidth: 2)
    }

    var pendingSection: some View {
        Group {
            if !actionRequests.isEmpty || !model.meshNeedsYouEvents.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Eyebrow(text: "Needs You")
                        Spacer()
                        Text("\(actionRequests.count + model.meshNeedsYouEvents.count)")
                            .font(.system(size: 12, weight: .heavy))
                            .foregroundStyle(Theme.riskHigh)
                    }
                    pendingRequests
                }
            }
        }
    }

    @ViewBuilder private var pendingRequests: some View {
        ForEach(orderedPending) { req in
            if model.isMcpAskApproval(req) {
                VStack(alignment: .leading, spacing: 10) {
                    Eyebrow(text: model.isMcpOpenAsk(req) ? "Question" : "Yes or No")
                    Text(req.title)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(Theme.ink)
                        .fixedSize(horizontal: false, vertical: true)
                    if model.approvalDecisionsInFlight[req.requestId] != nil {
                        Label(L("Waiting for the computer to confirm…"), systemImage: "hourglass")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(Theme.muted)
                    } else {
                        if model.isMcpOpenAsk(req) {
                            Button(L("Reply")) { beginReply(to: req.requestId, sessionId: req.sessionId) }
                                .buttonStyle(FilledButton(tint: Theme.codex,
                                                          textColor: Theme.glyphInk(for: "codex")))
                        } else {
                            HStack(spacing: 9) {
                                Button(L("No")) { model.answerQuestion(req.requestId, "no") }
                                    .buttonStyle(OutlineButton(tint: Theme.riskHigh))
                                Button(L("Yes")) { model.answerQuestion(req.requestId, "yes") }
                                    .buttonStyle(FilledButton(tint: Theme.ok))
                            }
                        }
                    }
                }
                .card()
                .overlay(focusedRing(req.requestId))
            } else {
                ApprovalCard(
                    req: req,
                    isWaiting: model.approvalDecisionsInFlight[req.requestId] != nil,
                    onApprove: { model.decide(req, "allow") },
                    onDeny: { model.decide(req, "deny") }
                )
                .overlay(focusedRing(req.requestId))
            }
        }
        ForEach(model.questions, id: \.requestId) { question in
            VStack(alignment: .leading, spacing: 10) {
                Eyebrow(text: "Question")
                Text(question.text)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Theme.ink)
                    .fixedSize(horizontal: false, vertical: true)
                if let id = question.requestId,
                   model.approvalDecisionsInFlight[id] != nil {
                    Label(L("Waiting for the computer to confirm…"), systemImage: "hourglass")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Theme.muted)
                } else {
                    Button(L("Reply")) {
                        if let id = question.requestId {
                            beginReply(to: id, sessionId: question.sessionId)
                        }
                    }
                    .buttonStyle(FilledButton(tint: Theme.codex,
                                              textColor: Theme.glyphInk(for: "codex")))
                }
            }
            .card()
        }
        ForEach(failedDeliveries) { delivery in
            VStack(alignment: .leading, spacing: 9) {
                Eyebrow(text: "Delivery failed")
                Text(delivery.error ?? L("The message could not reach the computer."))
                    .font(.system(size: 14, weight: .semibold))
                HStack(spacing: 9) {
                    Button(L("Retry")) { model.retryDelivery(delivery.id) }
                        .buttonStyle(FilledButton(tint: Theme.codex))
                    if let sessionId = delivery.sessionId,
                       let session = model.sessions.first(where: { $0.sessionId == sessionId }) {
                        Button(L("Open task")) { open(session) }
                            .buttonStyle(OutlineButton(tint: Theme.ink))
                    }
                }
            }
            .card()
        }
        ForEach(model.meshNeedsYouEvents) { event in
            meshNeedsYouCard(event)
        }
    }

    private func beginReply(to requestId: String, sessionId: String?) {
        replyRequestId = requestId
        composeSessionId = sessionId
        showNewTask = true
        composeFocused = true
    }

    func meshNeedsYouCard(_ event: ProjectMeshEvent) -> ProjectMeshNeedsYouCard {
        ProjectMeshNeedsYouCard(
            event: event,
            onAuthorize: { model.authorizeMeshEvent(event.eventId) },
            onOpen: { openMeshTask(event) },
            onDismiss: { model.dismissMeshEvent(event.eventId) }
        )
    }

    /// Route to the Task, not to a session that may not exist on this phone.
    func openMeshTask(_ event: ProjectMeshEvent) {
        openedTaskRoute = TaskRoute(projectId: event.projectId, taskId: event.taskId)
    }

    func meshSession(for event: ProjectMeshEvent) -> SessionInfo? {
        let snapshot = model.meshSnapshots[event.projectId]
        let owner = snapshot?.tasks.first(where: { $0.taskId == event.taskId })?.ownerSessionId
        return [owner, event.sourceSessionId, event.targetSessionId]
            .compactMap { $0 }
            .compactMap { id in
                (model.sessions + model.sessionHistory).first { $0.sessionId == id }
            }
            .first
    }

    // MARK: live sessions
}
