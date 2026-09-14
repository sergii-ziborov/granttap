import Foundation

/// Which transcript entry a usage row came from.
///
/// Tapping a call in history used to open the chat at its end, leaving the user
/// to find the call they had just tapped. The entry is recoverable: a stored
/// `sourceId` is the activity entry id, prefixed by the room it arrived from
/// and — for legacy rows that observed several capabilities in one call —
/// suffixed with the observation index.
enum CapabilityTranscriptLink {
    static func entryId(sourceId: String, roomId: String?) -> String? {
        var value = sourceId.trimmingCharacters(in: .whitespacesAndNewlines)
        if let roomId, !roomId.isEmpty, value.hasPrefix("\(roomId):") {
            value = String(value.dropFirst(roomId.count + 1))
        }
        if let marker = value.range(of: ":capability:", options: .backwards) {
            value = String(value[value.startIndex..<marker.lowerBound])
        }
        return value.isEmpty ? nil : value
    }
}
