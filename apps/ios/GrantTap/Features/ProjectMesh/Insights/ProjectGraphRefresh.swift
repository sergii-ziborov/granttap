import Foundation

enum ProjectGraphRefreshResult: Equatable {
    case completed, requested, partial, noRoute, failed

    var message: String {
        switch self {
        case .completed: return L("Computer analysis report received.")
        case .requested: return L("Requested on this Mesh's computers. Waiting for their reports.")
        case .partial: return L("Some computers could not refresh architecture. Check Health and retry.")
        case .noRoute: return L("No connected computer can receive this Mesh's analysis request.")
        case .failed: return L("Architecture refresh failed. Check the computer and repository binding in Health.")
        }
    }
}

/// Local ownership and relay connectivity are independent routes to a computer.
struct ProjectGraphRefreshPlan: Equatable {
    let local: Bool
    let rooms: [String]

    static func make(localProjectAvailable: Bool, sourceRooms: Set<String>,
                     connectedRooms: Set<String>, localRoom: String? = nil) -> Self {
        let rooms = sourceRooms.intersection(connectedRooms).filter {
            !localProjectAvailable || $0 != localRoom
        }.sorted()
        return .init(local: localProjectAvailable, rooms: rooms)
    }

    @MainActor
    func execute(localRefresh: () async throws -> Bool,
                 remoteRefresh: (String) async throws -> Void) async -> ProjectGraphRefreshResult {
        guard local || !rooms.isEmpty else { return .noRoute }
        var successes = 0
        var failures = 0
        if local {
            do {
                if try await localRefresh() { successes += 1 } else { failures += 1 }
            } catch { failures += 1 }
        }
        for room in rooms {
            do { try await remoteRefresh(room); successes += 1 } catch { failures += 1 }
        }
        if failures > 0 { return successes > 0 ? .partial : .failed }
        return rooms.isEmpty ? .completed : .requested
    }
}
