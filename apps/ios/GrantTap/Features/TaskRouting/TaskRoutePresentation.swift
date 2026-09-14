import Foundation

enum TaskPresence: Equatable {
    case offline
    case working
    case waiting
    case idle
}

struct TaskSendAvailability: Equatable {
    let message: String
    let blocksSending: Bool
}

enum TaskRoutePresentation {
    static func presence(nativeState: String, route: ChatComputerRoute?) -> TaskPresence {
        if let route, route.phase != .live { return .offline }
        switch nativeState {
        case "working": return .working
        case "waiting": return .waiting
        default: return .idle
        }
    }

    static func sessionMetadata(agent: String, model: String?, project: String? = nil,
                                route: ChatComputerRoute?) -> String {
        var values: [String] = []
        if let project = project?.trimmingCharacters(in: .whitespacesAndNewlines),
           !project.isEmpty, project != "No project" {
            values.append(project)
        }
        values.append(AgentIdentity.displayName(agent))
        if let model = model?.trimmingCharacters(in: .whitespacesAndNewlines), !model.isEmpty {
            values.append(model)
        }
        if let route {
            values.append(route.computerName)
            values.append(route.phase == .live ? L("Online") : L("Offline"))
        }
        return values.joined(separator: " · ")
    }

    static func deliveryStatus(
        _ delivery: OutgoingDelivery,
        route: ChatComputerRoute?,
        chatIsBusy: Bool = false
    ) -> String {
        if let route, route.phase != .live,
           delivery.state == .queued || delivery.state == .sending {
            return String(format: L("Queued until %@ reconnects"), route.computerName)
        }
        // The computer is fine; the chat itself is mid-turn. Saying so beats
        // "waiting for Mac", which points at the wrong thing entirely.
        if chatIsBusy, delivery.state == .sending {
            return L("Queued — the chat is busy, sending when it finishes")
        }
        switch delivery.state {
        case .queued: return String(format: L("Queued · attempt %d of 5"), delivery.attempts)
        case .sending: return L("Sent — waiting for Mac…")
        case .delivered: return L("Delivered to the computer")
        case .failed: return delivery.error ?? L("Delivery failed")
        }
    }

    static func allowedCount(_ values: [Bool]) -> Int? {
        values.isEmpty ? nil : values.filter { $0 }.count
    }

    static func providerUnavailableReason(_ agent: String) -> String? {
        // Cursor resume uses cursor-agent on the Mac. Do not hard-block the
        // composer here: the computer reports whether the CLI is reachable, and
        // a missing binary fails the send with a concrete Mac-side error.
        _ = agent
        return nil
    }

    static func sendAvailability(agent: String, route: ChatComputerRoute?) -> TaskSendAvailability? {
        if let reason = providerUnavailableReason(agent) {
            return TaskSendAvailability(message: reason, blocksSending: true)
        }
        guard let route else {
            return TaskSendAvailability(
                message: L("No computer is selected. Link or select a Mac/PC before sending."),
                blocksSending: true
            )
        }
        guard route.phase != .live else { return nil }
        return TaskSendAvailability(
            message: String(
                format: L("%@ is offline. Your message will stay queued until it reconnects."),
                route.computerName
            ),
            blocksSending: false
        )
    }
}
