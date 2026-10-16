import SwiftUI

extension ContentView {
    /// The model the next turn will use: this chat's own choice when the
    /// composer is aimed at a chat, and the agent's default when a Task is
    /// being started and there is no chat to inherit one from.
    var newTaskModelBinding: Binding<TurnModel?> {
        Binding(
            get: {
                guard let sessionId = selectedComposeSession?.sessionId else {
                    return model.turnOverrides.agentDefaults(for: activeComposeAgent).model
                }
                return model.turnOverrides.chatOverrides(sessionId).model
            },
            set: { picked in
                guard let sessionId = selectedComposeSession?.sessionId else {
                    var current = model.turnOverrides.agentDefaults(for: activeComposeAgent)
                    current.model = picked
                    model.turnOverrides.setAgentDefaults(current, for: activeComposeAgent)
                    return
                }
                var current = model.turnOverrides.chatOverrides(sessionId)
                current.model = picked
                model.turnOverrides.setChatOverrides(current, for: sessionId)
            }
        )
    }

    var newTaskEffortBinding: Binding<TurnEffort?> {
        Binding(get: {
            selectedComposeSession.map { model.turnOverrides.chatOverrides($0.sessionId).effort }
                ?? model.turnOverrides.agentDefaults(for: activeComposeAgent).effort
        }, set: { picked in
            if let sessionId = selectedComposeSession?.sessionId {
                var current = model.turnOverrides.chatOverrides(sessionId)
                current.effort = picked
                model.objectWillChange.send()
                model.turnOverrides.setChatOverrides(current, for: sessionId)
            } else {
                var current = model.turnOverrides.agentDefaults(for: activeComposeAgent)
                current.effort = picked
                model.objectWillChange.send()
                model.turnOverrides.setAgentDefaults(current, for: activeComposeAgent)
            }
        })
    }

    var composedTurnOverrides: TurnOverrides {
        let choices = selectedComposeSession.map {
            model.turnOverrides.resolved(sessionId: $0.sessionId, agent: activeComposeAgent)
        } ?? model.turnOverrides.agentDefaults(for: activeComposeAgent)
        return TurnOverrides(model: choices.model, effort: choices.effort)
    }

    var newTaskFallbackEffort: TurnEffort? {
        model.turnOverrides.agentDefaults(for: activeComposeAgent).effort
            ?? selectedComposeSession?.effort.flatMap(TurnEffort.init(rawValue:))
    }

}
