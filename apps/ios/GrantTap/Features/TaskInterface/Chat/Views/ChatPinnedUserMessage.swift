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
    static func topVisibleRow(_ positions: [ChatRowPosition], viewportHeight: CGFloat) -> String? {
        positions.filter { $0.maxY > 0 && $0.minY < viewportHeight }
            .min { $0.minY < $1.minY }?.id
    }

    static func entry(in rows: [ChatTimelineRow], topRowId: String?) -> ActivityEntry? {
        let first = rows.compactMap(userEntry).first
        guard let topRowId, let index = rows.firstIndex(where: { $0.id == topRowId }) else {
            return rows.reversed().compactMap(userEntry).first
        }
        return rows[...index].reversed().compactMap(userEntry).first ?? first
    }

    private static func userEntry(_ row: ChatTimelineRow) -> ActivityEntry? {
        guard case .item(.activity(let entry)) = row,
              entry.kind == "user", !entry.text.isEmpty else { return nil }
        return entry
    }
}
