import SwiftUI

struct ChatRowPosition: Equatable {
    let id: String
    let minY: CGFloat
    let maxY: CGFloat
}

struct ChatRowPositionKey: PreferenceKey {
    static var defaultValue: [ChatRowPosition] { [] }

    static func reduce(value: inout [ChatRowPosition], nextValue: () -> [ChatRowPosition]) {
        value.append(contentsOf: nextValue())
    }
}

/// The message pinned above the scroll view follows the turn being read.
enum ChatPinnedUserMessage {
    static func navigationEntry(in rows: [ChatTimelineRow], topRowId: String?,
                                afterJump: String?) -> ActivityEntry? {
        let current = entry(in: rows, topRowId: topRowId)
        guard let current, current.id == afterJump else { return current }
        return TranscriptRequestBoundary.previous(in: rows.compactMap(activityEntry), before: current.id)
    }

    static func topVisibleRow(_ positions: [ChatRowPosition], viewportHeight: CGFloat) -> String? {
        positions.filter { $0.maxY > 0 && $0.minY < viewportHeight }
            .min { $0.minY < $1.minY }?.id
    }

    static func entry(in rows: [ChatTimelineRow], topRowId: String?) -> ActivityEntry? {
        let entries = rows.compactMap(activityEntry)
        guard let topRowId, let index = rows.firstIndex(where: { $0.id == topRowId }) else {
            return TranscriptRequestBoundary.previous(in: entries, before: nil)
        }
        guard let candidate = rows[...index].reversed().compactMap(activityEntry)
            .first(where: TranscriptRequestBoundary.isRequest) else { return nil }
        return TranscriptRequestBoundary.request(containing: candidate.id, in: entries)
    }

    private static func activityEntry(_ row: ChatTimelineRow) -> ActivityEntry? {
        guard case .item(.activity(let entry)) = row else { return nil }
        return entry
    }
}
