import Foundation

/// A native provider id is not globally unique across linked computers. Keep
/// "never observed" separate from "observed in several authenticated rooms":
/// legacy unknown ids may be migrated in a one-room registry, while ambiguous
/// ids must always fail closed.
enum SessionRoomOwnership: Equatable {
    case unknown
    case exact(String)
    case ambiguous([String])

    var exactRoom: String? {
        guard case .exact(let room) = self else { return nil }
        return room
    }
}
