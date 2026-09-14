import Foundation

@MainActor
extension AppModel {
    var humanAttentionItems: [HumanAttentionItem] {
        let approvals = pending.map { request in
            HumanAttentionItem(
                id: request.requestId, kind: .approval, action: .decision,
                title: request.title, detail: request.cwd, agent: request.agent,
                command: request.command, risk: request.risk.rawValue,
                sessionId: request.sessionId, createdAt: request.createdAt,
                waitingForMachine: approvalDecisionsInFlight[request.requestId] != nil
            )
        }
        let openQuestions = questions.compactMap { event -> HumanAttentionItem? in
            guard let id = event.requestId else { return nil }
            return HumanAttentionItem(
                id: id, kind: .question, action: .reply, title: event.text,
                sessionId: event.sessionId, createdAt: event.createdAt
            )
        }
        let failed = deliveries.compactMap { delivery -> HumanAttentionItem? in
            guard delivery.state == .failed, delivery.admissionRejected != true else { return nil }
            return HumanAttentionItem(
                id: "delivery:\(delivery.id)", kind: .deliveryFailure,
                action: .retryOnPhone, title: L("Delivery failed"),
                detail: delivery.error, agent: delivery.agent,
                sessionId: delivery.sessionId, createdAt: delivery.updatedAt
            )
        }
        let mesh = meshNeedsYouEvents.map(meshAttentionItem)
        return Array((approvals + openQuestions + failed + mesh)
            .sorted { $0.createdAt > $1.createdAt }.prefix(128))
    }

    func meshAttentionItem(_ event: ProjectMeshEvent) -> HumanAttentionItem {
        let presentation = meshAttentionPresentation(event)
        return HumanAttentionItem(
            id: event.eventId, kind: presentation.kind, action: presentation.action,
            title: presentation.title, detail: presentation.detail,
            agent: meshProvider(for: event), sessionId: event.sourceSessionId,
            projectId: event.projectId, taskId: event.taskId, createdAt: event.createdAt
        )
    }

    private func meshAttentionPresentation(
        _ event: ProjectMeshEvent
    ) -> (kind: HumanAttentionKind, action: HumanAttentionAction, title: String, detail: String?) {
        switch event.eventType {
        case "HANDOFF_REQUEST":
            let capsule = event.payload.capsule
            let route = capsule.map {
                "\(MeshActorPresentation.routeName(provider: $0.sourceProvider, actorId: $0.sourceActorId)) → \(MeshActorPresentation.routeName(provider: $0.targetProvider, actorId: $0.targetActorId))"
            }
            return (.meshHandoff, .meshDecision, L("Continue handoff?"), route)
        case "AGENT_QUESTION":
            return (.meshQuestion, .meshReply,
                    event.payload.question ?? L("An agent needs your answer."), nil)
        case "CONFLICT":
            return (.meshConflict, .openPhone, L("Resource conflict"),
                    event.payload.summary ?? event.payload.reason ?? event.payload.resource)
        case "HANDOFF_REJECTED":
            return (.meshFailure, .openPhone, L("Handoff failed"), event.payload.reason)
        default:
            return (.meshFailure, .openPhone, L("Task blocked"),
                    event.payload.reason ?? event.payload.summary)
        }
    }

    private func meshProvider(for event: ProjectMeshEvent) -> String? {
        meshSnapshots[event.projectId]?.executions.first {
            $0.sessionId == event.sourceSessionId
        }?.provider ?? (event.sourceActorId == nil ? nil : "grok_bot")
    }

    /// Mirror the current human-attention layer and bounded task state to Watch.
    func pushToWatch(force: Bool = false) {
        let approvals = pending.map {
            WatchApproval(id: $0.requestId, agent: $0.agent, title: $0.title,
                          command: $0.command, risk: $0.risk.rawValue, cwd: $0.cwd,
                          sessionId: $0.sessionId,
                          waitingForMachine: approvalDecisionsInFlight[$0.requestId] != nil)
        }
        let watchQuestions = questions.compactMap { event -> WatchQuestion? in
            guard let id = event.requestId else { return nil }
            return WatchQuestion(id: id, text: event.text, sessionId: event.sessionId)
        }
        let watchSessions = sessions.map {
            WatchSession(id: $0.sessionId, agent: $0.agent, title: $0.displayTitle,
                         state: $0.state, tokensSession: $0.tokensSession,
                         tokensLastTurn: $0.tokensLastTurn, elapsedSec: Int($0.elapsed),
                         contextTokensUsed: $0.contextTokensUsed,
                         contextWindow: $0.contextWindow, lastActivityAt: $0.lastActivityAt)
        }
        let watchActivities = activities.values.map { activity in
            WatchActivity(sessionId: activity.sessionId, agent: activity.agent,
                          state: activity.state, entries: activity.entries.map {
                              WatchActivityEntry(id: $0.id, kind: $0.kind, text: $0.text,
                                                 createdAt: $0.createdAt)
                          })
        }
        let watchAgents = agentIntegrations.map {
            WatchAgentIntegration(agent: $0.agent, installed: $0.installed,
                                  hookConfigured: $0.hookConfigured)
        }
        WatchBridge.shared.push(WatchState(
            attention: humanAttentionItems, approvals: approvals, questions: watchQuestions,
            sessions: watchSessions, activities: watchActivities, agents: watchAgents,
            machine: machineName, connected: connected
        ), force: force)
    }
}
