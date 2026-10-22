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
    @State var composerDraft = ChatComposerDraft()
    var draft: String {
        get { composerDraft.text }
        nonmutating set { composerDraft.text = newValue }
    }
    var draftBinding: Binding<String> {
        Binding(get: { composerDraft.text }, set: { composerDraft.text = $0 })
    }
    @State var chatFocused = false
    @State var attachments: [AttachmentDraft] = []
    @State var attachmentError: String?
    @State var selectedMcp: String?
    @State var selectedSkill: String?
    @State private var transcriptCache = ChatTranscriptCache()
    @State var chatIsAtBottom = true
    @State var transcriptFitsViewport = false
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
    @State var historyPreservedBottom = false
    @State var historyReadingActive = false
    @State var userMessageAnchor: String?
    @State var requestJumpSettling = false
    @State var pendingUserJump = false
    /// Per-chat answer settings; unset means "use whatever the chat already has".
    @State var showCapabilities = false
    @State var showProjectMesh = false
    @State var showHandoff = false
    @State var showTransferContinuation = false
    @State var showSchedule = false
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
        _composerDraft = State(initialValue: ChatComposerDraft(text: initialDraft))
        #if DEBUG
        if ProcessInfo.processInfo.environment["GRANTTAP_DEMO"] == "1",
           ProcessInfo.processInfo.environment["GRANTTAP_TEST_CHAT_QUEUE"] == "1" {
            _composerDraft = State(initialValue: ChatComposerDraft(text: "Next queued message"))
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
        var current = model.sessions.first(where: { $0.sessionId == chatSessionId })
            ?? model.sessionHistory.first(where: { $0.sessionId == chatSessionId })
            ?? model.archivedSessions[chatSessionId]
            ?? model.sessions.first(where: { $0.sessionId == session.sessionId })
            ?? session
        if ProjectMeshTaskTitle.presentable(current.title ?? "") == nil {
            current.title = ProjectMeshTaskTitle.presentable(session.title ?? "")
        }
        return current
    }

    var entries: [ActivityEntry] {
        model.activities[chatSessionId]?.entries
            ?? model.activities[session.sessionId]?.entries
            ?? []
    }

    var rootEntries: [ActivityEntry] {
        transcriptPresentation.rootEntries
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

    var visibleTimeline: [CombinedTaskTimelineItem] { transcriptPresentation.items }

    var timelineRows: [ChatTimelineRow] { transcriptPresentation.rows }
    var requestIndex: TranscriptRequestIndex { transcriptPresentation.requests }
    var requestNavigation: ChatRequestNavigation { transcriptPresentation.navigation }

    var transcriptRevision: ChatTranscriptRevision {
        let executions = taskExecutionSessionIds
        return ChatTranscriptRevision(meshEvents: model.meshEvents(forTaskId: currentSession.taskId),
                               executions: executions,
                               activityRevisions: (executions + [session.sessionId]).map { model.activityRevisions[$0] ?? 0 },
                               threads: taskExecutionSessionIds.flatMap {
                                   model.knownSession(for: $0, preferredAgent: nil)?.childThreads ?? []
                               },
                               roomId: model.connectionRegistry.preferredId)
    }

    func recordedChanges(for finalId: String) -> [RecordedFileChange] {
        transcriptPresentation.replyChanges[finalId] ?? []
    }

    var currentReplyFinalId: String? { transcriptPresentation.currentFinalId }
    var currentReplyFiles: [RecordedFileChange] { transcriptPresentation.currentFiles }
    var preparedChildThreads: [ChildThreadDisplayRow] { transcriptPresentation.childThreads }

    var transcriptPresentation: ChatTranscriptPresentation {
        transcriptCache.value(sessionId: session.sessionId, revision: transcriptRevision) { retained in
            let timeline = combinedTimeline
            let allEntries = taskExecutionEntries
            let threads = taskExecutionSessionIds.flatMap { id in
                ChildThreadTree.rows(rootId: id,
                    threads: model.knownSession(for: id, preferredAgent: nil)?.childThreads ?? [],
                    activity: model.activities[id]?.entries ?? [])
            }
            return ChatTranscriptPresentation(items: timeline.isEmpty ? retained : timeline,
                                               entries: allEntries, childThreads: threads)
        }
    }

    var body: some View { chatScreen.environment(\.messageImageSessionId, chatSessionId) }
}
