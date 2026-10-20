import Foundation

/// A complete tower inventory can still carry bounded symbol or link evidence.
enum ProjectCodeMapScope: Equatable {
    case complete, missingTowers, limitedDetails

    init(_ map: ProjectCodeMap) {
        if map.files.count < map.totalFiles || (map.externals?.count ?? 0) < (map.totalExternals ?? 0) {
            self = .missingTowers
        } else {
            self = map.truncated ? .limitedDetails : .complete
        }
    }

    var partialTitle: String? {
        switch self {
        case .complete: return nil
        case .missingTowers: return L("Partial map")
        case .limitedDetails: return L("Partial source details")
        }
    }
}
