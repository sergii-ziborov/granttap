import SwiftUI
import PhotosUI
import UniformTypeIdentifiers
import UIKit

struct SessionCard: View {
    let session: SessionInfo
    var route: ChatComputerRoute? = nil
    var mesh: ProjectMeshSnapshot? = nil
    var squareTrailingEdge = false

    private var accent: Color { Theme.accent(for: session.agent) }

    private var cardShape: SessionCardShape {
        SessionCardShape(squareTrailingEdge: squareTrailingEdge)
    }

    private var presence: TaskPresence {
        TaskRoutePresentation.presence(nativeState: session.state, route: route)
    }

    private var stateLabel: String {
        switch presence {
        case .offline: return L("Offline")
        case .working: return L("Working")
        case .waiting: return L("Waiting")
        case .idle: return L("Idle")
        }
    }

    private var stateColor: Color {
        switch presence {
        case .working: return Theme.ok
        case .waiting: return Theme.riskMed
        case .offline, .idle: return Theme.muted
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 10) {
                AgentGlyph(agent: session.agent, size: 24)

                VStack(alignment: .leading, spacing: 2) {
                    Text(session.displayTitle)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Theme.ink)
                        .lineLimit(1)
                    Text(TaskRoutePresentation.sessionMetadata(
                        agent: session.agent,
                        model: session.model,
                        project: session.projectGroupTitle,
                        route: route
                    ))
                    .font(.system(size: 10.5, weight: .semibold))
                    .foregroundStyle(route?.phase == .live ? Theme.muted : Theme.riskMed)
                    .lineLimit(1)
                }

                Spacer(minLength: 6)

                HStack(spacing: 5) {
                    Circle()
                        .fill(stateColor)
                        .frame(width: 7, height: 7)
                    Text(stateLabel)
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(stateColor)
                }
            }

            HStack(spacing: 8) {
                Text(meshSummary
                     ?? (session.summary?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
                         ? session.summary! : session.projectGroupTitle))
                    .font(.system(size: 11.5))
                    .foregroundStyle(Theme.muted)
                    .lineLimit(1)
                Spacer(minLength: 4)
                if let percent = contextPercent, percent >= 65 {
                    Text("\(L("Context")) \(percent)%")
                        .font(.system(size: 10.5, weight: .bold))
                        .foregroundStyle(percent >= 85 ? Theme.riskMed : Theme.muted)
                }
            }
        }
        .padding(12)
        // Use the container proposal, not UIScreen width: iPad Split View and
        // Stage Manager can be much narrower than the physical display.
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.raised, in: cardShape)
        .overlay(cardShape.stroke(Theme.line, lineWidth: 1))
    }

    private var contextPercent: Int? {
        guard let used = session.contextTokensUsed,
              let window = session.contextWindow, window > 0 else { return nil }
        return Int((Double(used) / Double(window) * 100).rounded())
    }

    var meshSummary: String? {
        guard let taskId = session.taskId else { return nil }
        let executions = mesh?.executions.filter { $0.taskId == taskId } ?? []
        guard executions.count > 1 else { return nil }
        let agents = Set(executions.map(\.provider)).count
        let computers = Set(executions.map(\.computerId)).count
        let route = executions.map { AgentIdentity.shortName($0.provider) }
            .reduce(into: [String]()) { result, name in
                if result.last != name { result.append(name) }
            }
            .joined(separator: " → ")
        return "\(agents) agents · \(computers) computers · \(route)"
    }
}

/// iOS 15-compatible per-corner card shape. UnevenRoundedRectangle starts at
/// iOS 16 and made the universal deployment target impossible to compile.
struct SessionCardShape: Shape {
    let squareTrailingEdge: Bool

    func path(in rect: CGRect) -> Path {
        let corners: UIRectCorner = squareTrailingEdge
            ? [.topLeft, .bottomLeft]
            : [.allCorners]
        return Path(UIBezierPath(
            roundedRect: rect,
            byRoundingCorners: corners,
            cornerRadii: CGSize(width: Theme.radius, height: Theme.radius)
        ).cgPath)
    }
}

/// Swipe-to-reveal action for cards that live in a ScrollView rather than a List.
/// A UIKit pan recognizer is used here because SwiftUI's `DragGesture` claims a
/// touch before its `onChanged` direction check runs. That makes the parent
/// ScrollView appear frozen whenever a vertical drag starts on a card.
