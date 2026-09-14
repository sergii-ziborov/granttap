import SwiftUI

struct ProjectMeshNeedsYouCard: View {
    let event: ProjectMeshEvent
    let onAuthorize: () -> Void
    let onOpen: () -> Void
    let onDismiss: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Eyebrow(text: eyebrow)
            Text(title)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(Theme.ink)
            if let detail {
                Text(detail).font(.system(size: 13)).foregroundStyle(Theme.muted)
            }
            HStack(spacing: 9) {
                if event.eventType == "HANDOFF_REQUEST" {
                    Button(L("Continue handoff"), action: onAuthorize)
                        .buttonStyle(FilledButton(tint: Theme.codex))
                } else {
                    Button(L("Open task"), action: onOpen)
                        .buttonStyle(FilledButton(tint: Theme.codex))
                }
                Button(secondaryLabel, action: onDismiss)
                    .buttonStyle(OutlineButton(tint: Theme.ink))
            }
        }
        .card()
    }

    var eyebrow: String {
        switch event.eventType {
        case "HANDOFF_REQUEST": return "Task handoff"
        case "CONFLICT": return "Resource conflict"
        case "AGENT_QUESTION": return "Agent question"
        default: return "Blocked task"
        }
    }

    var title: String {
        event.payload.question ?? event.payload.reason
            ?? event.payload.capsule?.goal ?? "This task needs your decision."
    }

    var detail: String? {
        if let capsule = event.payload.capsule {
            return "\(MeshActorPresentation.routeName(provider: capsule.sourceProvider, actorId: capsule.sourceActorId)) → \(MeshActorPresentation.routeName(provider: capsule.targetProvider, actorId: capsule.targetActorId)) · \(capsule.targetComputer)"
        }
        return event.payload.resource
    }

    var secondaryLabel: String {
        switch event.eventType {
        case "HANDOFF_REQUEST": return L("Decline")
        case "AGENT_QUESTION": return L("Remind me later")
        default: return L("Acknowledge")
        }
    }
}

enum CombinedTaskTimelineItem: Identifiable {
    case activity(ActivityEntry)
    case mesh(ProjectMeshEvent)

    var id: String {
        switch self {
        case .activity(let entry): return "activity:\(entry.id)"
        case .mesh(let event): return "mesh:\(event.eventId)"
        }
    }

    var createdAt: Double {
        switch self {
        case .activity(let entry): return entry.createdAt
        case .mesh(let event): return event.createdAt
        }
    }
}

struct ProjectMeshTimelineRow: View {
    let event: ProjectMeshEvent

    var body: some View {
        HStack(alignment: .top, spacing: 9) {
            Image(systemName: icon)
                .frame(width: 22, height: 22)
                .foregroundStyle(Theme.codex)
            VStack(alignment: .leading, spacing: 3) {
                Text(label).font(.system(size: 12, weight: .bold))
                if let detail {
                    Text(detail).font(.system(size: 12)).foregroundStyle(Theme.muted)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 4)
    }

    var icon: String {
        switch event.eventType {
        case "HANDOFF_REQUEST", "HANDOFF_ACCEPTED": return "arrow.right.arrow.left"
        case "AGENT_QUESTION", "AGENT_ANSWER": return "bubble.left.and.bubble.right"
        case "CONFLICT", "TASK_BLOCKED": return "exclamationmark.triangle"
        case "TASK_COMPLETED": return "checkmark.circle"
        default: return "point.3.connected.trianglepath.dotted"
        }
    }

    var label: String {
        switch event.eventType {
        case "HANDOFF_REQUEST": return L("Handoff requested")
        case "HANDOFF_ACCEPTED": return L("Handoff accepted")
        case "HANDOFF_REJECTED": return L("Handoff failed")
        case "AGENT_QUESTION": return L("Agent asked")
        case "AGENT_ANSWER": return L("Agent answered")
        case "TASK_BLOCKED": return L("Task blocked")
        case "TASK_COMPLETED": return L("Task completed")
        case "RESOURCE_CLAIM": return L("Resource claimed")
        case "CONFLICT": return L("Conflict detected")
        default: return event.eventType.replacingOccurrences(of: "_", with: " ").capitalized
        }
    }

    var detail: String? {
        let message = event.payload.summary ?? event.payload.question ?? event.payload.answer
            ?? event.payload.reason ?? event.payload.resource
        guard let actorId = event.sourceActorId else { return message }
        let actor = MeshActorPresentation.name(actorId)
        return message.map { "\(actor) · Grok Bot — \($0)" } ?? "\(actor) · Grok Bot"
    }
}
