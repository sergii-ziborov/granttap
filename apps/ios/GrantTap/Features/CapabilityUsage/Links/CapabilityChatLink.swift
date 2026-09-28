import Foundation

/// Whether a recorded call may open the chat it came from.
///
/// Three lists show calls, and each must refuse the same things: a target
/// whose room this phone no longer knows, a session id that is ambiguous across
/// computers, or a room that is not the one the event was recorded from. One
/// decision here, so a call opens exactly the transcript it belongs to or none.
enum CapabilityChatLink {
    @MainActor
    static func target(for event: CapabilityUsageEvent, model: AppModel) -> CapabilityChatTarget? {
        guard let target = event.deepLinkTarget,
              target.kind == "chat",
              event.sourceRoom == target.roomId,
              event.sessionId == target.sessionId,
              model.connectionRegistry.connections.contains(where: { $0.id == target.roomId })
        else { return nil }
        switch model.sessionRoomOwnership(forSessionId: target.sessionId) {
        case .unknown:
            return target
        case .exact(let owner):
            return owner == target.roomId ? target : nil
        case .ambiguous:
            // Raw provider ids are not room-qualified throughout the legacy
            // catalog yet. Fail closed instead of opening a mixed transcript.
            return nil
        }
    }
}
