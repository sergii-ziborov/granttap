import Foundation

/// One projection per conversation revision, including the first screen layout.
final class ChatTranscriptCache {
    private var sessionId: String?
    private var revision: ChatTranscriptRevision?
    private var presentation: ChatTranscriptPresentation?

    func value(sessionId: String, revision: ChatTranscriptRevision,
               build: ([CombinedTaskTimelineItem]) -> ChatTranscriptPresentation) -> ChatTranscriptPresentation {
        if self.sessionId == sessionId, self.revision == revision, let presentation { return presentation }
        let retained = self.sessionId == sessionId && self.revision?.roomId == revision.roomId
            ? presentation?.items ?? [] : []
        let value = build(retained)
        self.sessionId = sessionId
        self.revision = revision
        presentation = value
        return value
    }
}
