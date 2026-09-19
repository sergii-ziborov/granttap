import SwiftUI

struct TaskChatView: View {
    let session: SessionInfo
    /// Opened from a call in history: land on that call, not at the end.
    var focusEntryId: String? = nil
    @EnvironmentObject private var environmentModel: AppModel
    var modelOverride: AppModel? = nil
    @State var focusHonoured = false
    /// Briefly marks the entry a history row was tapped from.
    @State var highlightedEntryId: String?
    /// Folded like a run of CLI calls. Opening every conversation broke GrantTap.
    @State var agentThreadsExpanded = false
    @State var draft = ""
    @FocusState var chatFocused: Bool
    @State var attachments: [AttachmentDraft] = []
    @State var attachmentError: String?
    @State var selectedMcp: String?
    @State var selectedSkill: String?
    @State var loadTimedOut = false
    /// Per-chat answer settings; unset means "use whatever the chat already has".
    @State var showCapabilities = false
    @State var showProjectMesh = false
    @State var showHandoff = false
    @State var showReport = false
    @State var replyRequestId: String?
    @State var rowFrames: [String: CGRect] = [:]
    @State var scrollViewportHeight: CGFloat = 0
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
        initialLoadTimedOut: Bool = false,
        initialShowCapabilities: Bool = false,
        initialAgentThreadsExpanded: Bool = false,
        dictator: Dictator? = nil
    ) {
        self.session = session
        self.focusEntryId = focusEntryId
        self.modelOverride = modelOverride
        _draft = State(initialValue: initialDraft)
        _attachments = State(initialValue: initialAttachments)
        _selectedMcp = State(initialValue: initialSelectedMcp)
        _selectedSkill = State(initialValue: initialSelectedSkill)
        _replyRequestId = State(initialValue: initialReplyRequestId)
        _attachmentError = State(initialValue: initialAttachmentError)
        _loadTimedOut = State(initialValue: initialLoadTimedOut)
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

    var body: some View {
        VStack(spacing: 0) {
            taskStatusStrip
            ScrollViewReader { proxy in
                ZStack(alignment: .bottomTrailing) {
                    ZStack(alignment: .top) {
                        chatScroll(proxy)
                        if let pinned = pinnedUserLine {
                            ChatStickyUserBar(text: pinned.text, accent: accent) {
                                highlightedEntryId = pinned.entryId
                                withAnimation(.easeOut(duration: 0.22)) {
                                    proxy.scrollTo(pinned.scrollId, anchor: .top)
                                }
                                Task { @MainActor in
                                    try? await Task.sleep(nanoseconds: 2_400_000_000)
                                    withAnimation(.easeInOut(duration: 0.35)) { highlightedEntryId = nil }
                                }
                            }
                        }
                    }
                    if showJumpToLatest {
                        ChatJumpToLatestButton { scrollToBottom(proxy) }
                    }
                }
            }

            // Compact strip above composer — never full ApprovalCards (half-screen gap).
            InChatApprovalsBar(sessionId: chatSessionId) { requestId in
                replyRequestId = requestId
                chatFocused = true
            }
            .environmentObject(model)
            composer
        }
        .background(Theme.canvas(for: currentSession.agent))
        .navigationTitle(currentSession.displayTitle)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                if let snapshot = projectMeshSnapshot,
                   ProjectMeshLogic.visibleProject(snapshot) {
                    Button { showProjectMesh = true } label: {
                        Image(systemName: "point.3.connected.trianglepath.dotted")
                    }
                    .accessibilityLabel("Project Mesh")
                }
                taskControlsMenu
            }
        }
        .sheet(isPresented: $showCapabilities) {
            ChatCapabilitySheet(
                sessionId: chatSessionId,
                session: currentSession,
                rows: capabilityRows,
                accent: accent,
                onToggle: toggleCapability
            ).environmentObject(model)
        }
        .sheet(isPresented: $showHandoff) {
            TaskHandoffSheet(session: currentSession, model: model)
        }
        .sheet(isPresented: $showReport) {
            ReportExportSheet(report: model.report(for: reportScope))
        }
        .sheet(isPresented: $showProjectMesh) {
            // The same chrome as Settings: one stack, the title, a Done — not a
            // bare NavigationView whose large title floated over an empty band.
            CompatNavigationStack {
                if let snapshot = projectMeshSnapshot {
                    ProjectMeshView(snapshot: snapshot, model: model) { session in
                        model.sessionToOpen = session.sessionId
                        showProjectMesh = false
                    }
                }
            }
        }
        .onAppear {
            loadTimedOut = activitySnapshotKnown && entries.isEmpty && childThreads.isEmpty
            model.subscribeSession(chatSessionId, active: true,
                                   source: "phone-chat:\(chatSessionId)")
            Task { @MainActor in
                await focusComposerForDebugCapture()
                try? await Task.sleep(nanoseconds: 4_000_000_000)
                if entries.isEmpty && childThreads.isEmpty { loadTimedOut = true }
            }
        }
        .onChange(of: entries.count) { count in
            if count > 0 { loadTimedOut = false }
        }
        .onChange(of: activitySnapshotKnown) { known in
            if known, entries.isEmpty, childThreads.isEmpty { loadTimedOut = true }
        }
        .onDisappear {
            model.subscribeSession(chatSessionId, active: false,
                                   source: "phone-chat:\(chatSessionId)")
        }
    }
}
