import SwiftUI

struct TaskChatView: View {
    let session: SessionInfo
    /// Opened from a call in history: land on that call, not at the end.
    var focusEntryId: String? = nil
    @EnvironmentObject private var environmentModel: AppModel
    @Environment(\.dismiss) var dismiss
    @Environment(\.openMeshInMainWindow) var mainWindowMeshAction
    var modelOverride: AppModel? = nil
    var onOpenMesh: ((String, String) -> Void)? = nil
    @State var focusHonoured = false
    /// Briefly marks the entry a history row was tapped from.
    @State var highlightedEntryId: String?
    /// The agent conversations start folded, the way a run of CLI calls does.
    @State var agentThreadsExpanded = false
    @State var draft = ""
    @FocusState var chatFocused: Bool
    @State var attachments: [AttachmentDraft] = []
    @State var attachmentError: String?
    @State var selectedMcp: String?
    @State var selectedSkill: String?
    @State private var retainedTimeline: RetainedChatContent<CombinedTaskTimelineItem>?
    @State var chatIsAtBottom = true
    @State var localActivityLoading = false
    @State var localActivityError = false
    @State var localSending = false
    @State var localSendError: String?
    @State var topVisibleTranscriptRow: String?
    @State var historyLoading = false
    @State var historyAutoPagingReady = false
    @State var historyError = false
    @State var pendingHistoryCursor: String?
    @State var historyScrollAnchor: String?
    /// Per-chat answer settings; unset means "use whatever the chat already has".
    @State var showCapabilities = false
    @State var showProjectMesh = false
    @State var showHandoff = false
    @State var showReport = false
    @State var replyRequestId: String?
    @StateObject var dictator: Dictator

    var model: AppModel { modelOverride ?? environmentModel }

    init(
        session: SessionInfo,
        focusEntryId: String? = nil,
        modelOverride: AppModel? = nil,
        initialDraft: String = "",
        initialAttachments: [AttachmentDraft] = [],
        initialSelectedMcp: String? = nil,
        initialSelectedSkill: String? = nil,
        initialReplyRequestId: String? = nil,
        initialAttachmentError: String? = nil,
        initialShowCapabilities: Bool = false,
        initialAgentThreadsExpanded: Bool = false,
        onOpenMesh: ((String, String) -> Void)? = nil,
        dictator: Dictator? = nil
    ) {
        self.session = session
        self.focusEntryId = focusEntryId
        self.modelOverride = modelOverride
        self.onOpenMesh = onOpenMesh
        _draft = State(initialValue: initialDraft)
        #if DEBUG
        if ProcessInfo.processInfo.environment["GRANTTAP_DEMO"] == "1",
           ProcessInfo.processInfo.environment["GRANTTAP_TEST_CHAT_QUEUE"] == "1" {
            _draft = State(initialValue: "Next queued message")
        }
        #endif
        _attachments = State(initialValue: initialAttachments)
        #if DEBUG
        if ProcessInfo.processInfo.environment["GRANTTAP_DEMO"] == "1",
           ProcessInfo.processInfo.environment["GRANTTAP_TEST_ATTACHMENT_FILES"] == "1" {
            _attachments = State(initialValue:
                ProcessInfo.processInfo.environment["GRANTTAP_TEST_ATTACHMENT_SCROLL"] == "1"
                    ? AttachmentPreviewFixture.scrollDrafts : AttachmentPreviewFixture.drafts)
        }
        #endif
        _selectedMcp = State(initialValue: initialSelectedMcp)
        _selectedSkill = State(initialValue: initialSelectedSkill)
        _replyRequestId = State(initialValue: initialReplyRequestId)
        _attachmentError = State(initialValue: initialAttachmentError)
        _showCapabilities = State(initialValue: initialShowCapabilities)
        _agentThreadsExpanded = State(initialValue: initialAgentThreadsExpanded)
        _dictator = StateObject(wrappedValue: dictator ?? Dictator())
    }

    /// Follow stub→Mac remap so sends APPEND into the live agent session.
    var chatSessionId: String { model.resolvedSessionId(session.sessionId) }

    var currentSession: SessionInfo {
        model.sessions.first(where: { $0.sessionId == chatSessionId })
            ?? model.sessionHistory.first(where: { $0.sessionId == chatSessionId })
            ?? model.archivedSessions[chatSessionId]
            ?? model.sessions.first(where: { $0.sessionId == session.sessionId })
            ?? session
    }

    var entries: [ActivityEntry] {
        model.activities[chatSessionId]?.entries
            ?? model.activities[session.sessionId]?.entries
            ?? []
    }

    var rootEntries: [ActivityEntry] {
        entries.filter { $0.childThreadId == nil }
    }

    /// Empty Mac ack stored — leave spinner (same path as applyActivity).
    var activitySnapshotKnown: Bool {
        model.activities[chatSessionId] != nil
            || model.activities[session.sessionId] != nil
    }

    var accent: Color { Theme.accent(for: currentSession.agent) }
    var controlSupport: ProviderControlSupport {
        ProviderControlSupport.forAgent(currentSession.agent)
    }

    var liveStamp: String {
        let gen = model.activities[chatSessionId]?.generatedAt
            ?? model.activities[session.sessionId]?.generatedAt ?? 0
        return "\(chatSessionId.prefix(8))-\(entries.count)-\(Int(gen))"
    }

    var visibleTimeline: [CombinedTaskTimelineItem] {
        retainedTimeline?.visible(
            current: combinedTimeline, sessionId: session.sessionId,
            roomId: model.connectionRegistry.preferredId
        ) ?? combinedTimeline
    }

    func retainCurrentTranscript() {
        let timeline = combinedTimeline
        guard !timeline.isEmpty else { return }
        retainedTimeline = RetainedChatContent(
            sessionId: session.sessionId, roomId: model.connectionRegistry.preferredId,
            items: timeline
        )
    }

    var body: some View { chatScreen }
}
