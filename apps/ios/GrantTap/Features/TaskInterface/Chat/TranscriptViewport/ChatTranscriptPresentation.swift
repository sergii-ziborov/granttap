import Foundation

/// Prepared once per transcript/Mesh revision, rather than per scroll or keystroke.
struct ChatTranscriptPresentation {
    let items: [CombinedTaskTimelineItem]
    let rows: [ChatTimelineRow]
    let rootEntries: [ActivityEntry]
    let sourceEntries: [ActivityEntry]
    let replyChanges: [String: [RecordedFileChange]]
    let currentFinalId: String?
    let currentFiles: [RecordedFileChange]
    let childThreads: [ChildThreadDisplayRow]
    let requests: TranscriptRequestIndex
    let navigation: ChatRequestNavigation

    init(items: [CombinedTaskTimelineItem], entries: [ActivityEntry],
         childThreads: [ChildThreadDisplayRow] = []) {
        self.items = items
        sourceEntries = entries
        rows = ChatActivityGrouping.rows(items)
        rootEntries = entries.filter { $0.childThreadId == nil }
        requests = TranscriptRequestIndex(rootEntries)
        navigation = ChatRequestNavigation(rows: rows)
        replyChanges = ChatFileChanges.replies(in: rootEntries)
        currentFinalId = ChatFileChanges.currentReplyFinalId(entries: rootEntries)
        currentFiles = ChatFileChanges.currentReply(entries: rootEntries)
        self.childThreads = childThreads
    }
}

struct ChatTranscriptRevision: Equatable {
    let meshEvents: [ProjectMeshEvent]
    let executions: [String]
    let activityRevisions: [UInt64]
    let threads: [ChildThreadInfo]
    let roomId: String?
}
