import SwiftUI

extension TaskChatView {
    @ViewBuilder
    var chatScreen: some View {
        if #available(iOS 16.0, *) {
            chatContent.toolbar(.hidden, for: .tabBar)
        } else {
            chatContent
        }
    }

    private var chatContent: some View {
        VStack(spacing: 0) {
            #if targetEnvironment(macCatalyst)
            macChatHeader
            #endif
            taskStatusStrip
            chatTranscript
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            chatComposerInset
                .background(
                    (currentSession.agent.lowercased().contains("claude")
                        ? Theme.claudeCanvas : Theme.surface).ignoresSafeArea(edges: .bottom)
                )
        }
        .background(Theme.canvas(for: currentSession.agent))
        #if targetEnvironment(macCatalyst)
        .navigationBarHidden(true)
        #else
        .navigationTitle(currentSession.displayTitle)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { chatToolbar }
        #endif
        .sheet(isPresented: $showCapabilities) { capabilitiesSheet }
        .sheet(isPresented: $showHandoff) {
            TaskHandoffSheet(session: currentSession, model: model)
        }
        .sheet(isPresented: $showReport) {
            ReportExportSheet(report: model.report(for: reportScope))
        }
        #if !targetEnvironment(macCatalyst)
        .sheet(isPresented: $showProjectMesh) { projectMeshSheet }
        #endif
        .onAppear(perform: chatAppeared)
        #if targetEnvironment(macCatalyst)
        .task(id: chatSessionId) { await loadLocalConversation() }
        #endif
        .onChange(of: combinedTimeline.map(\.id)) { _ in retainCurrentTranscript() }
        .onDisappear(perform: chatDisappeared)
    }

    private var chatTranscript: some View {
        ScrollViewReader { proxy in
            VStack(spacing: 0) {
                latestUserMessageButton(proxy)
                GeometryReader { viewport in
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 14) {
                            olderMessagesHeader(proxy)
                            transcriptRows(proxy)
                            DeliveryStatusList(
                                deliveries: model.orphanDeliveries(for: chatSessionId)
                            )
                            Color.clear.frame(height: 1)
                                .background(GeometryReader { marker in
                                    Color.clear.preference(
                                        key: ChatBottomPositionKey.self,
                                        value: marker.frame(in: .named("chat-transcript")).maxY
                                    )
                                })
                                .id("chat-bottom")
                        }
                        .padding(16)
                    }
                    .coordinateSpace(name: "chat-transcript")
                    .onPreferenceChange(ChatHistoryPositionKey.self) { position in
                        // The first layout exposes the header briefly. Arm only
                        // after it has actually scrolled above the viewport.
                        if let position, position < -100 { historyAutoPagingReady = true }
                        if historyAutoPagingReady, let position, position >= -100, position < viewport.size.height,
                           !chatIsAtBottom, !historyError { loadEarlierMessages(proxy) }
                    }
                    .onPreferenceChange(ChatRowPositionKey.self) { positions in
                        guard let top = ChatPinnedUserMessage.topVisibleRow(
                            positions, viewportHeight: viewport.size.height
                        ) else { return }
                        if topVisibleTranscriptRow != top { topVisibleTranscriptRow = top }
                    }
                    .onPreferenceChange(ChatBottomPositionKey.self) { position in
                        guard let position else {
                            if !visibleTimeline.isEmpty { chatIsAtBottom = false }
                            return
                        }
                        let atBottom = position <= viewport.size.height + 36
                        chatIsAtBottom = atBottom
                    }
                    .overlay(alignment: .bottomTrailing) {
                        if !chatIsAtBottom && !visibleTimeline.isEmpty {
                            Button {
                                userMessageAnchor = nil
                                pendingUserJump = false
                                withAnimation(.easeOut(duration: 0.2)) {
                                    proxy.scrollTo("chat-bottom", anchor: .bottom)
                                }
                            } label: {
                                Image(systemName: "arrow.down")
                                    .font(.system(size: 17, weight: .semibold))
                                    .frame(width: 44, height: 44)
                                    .background(Theme.surface, in: Circle())
                                    .overlay(Circle().stroke(Theme.line, lineWidth: 1))
                            }
                            .accessibilityLabel(L("Jump to latest messages"))
                            .accessibilityIdentifier("chat.jumpToLatest")
                            .padding(.trailing, 16)
                            .padding(.bottom, 10)
                        }
                    }
                }
            }
            .onAppear {
                historyReadingActive = true
                settleScroll(proxy)
                ensurePreviousRequest(proxy)
            }
            .onDisappear { historyReadingActive = false }
            .onChange(of: transcriptHistory) { _ in
                historyArrived(proxy)
                ensurePreviousRequest(proxy)
            }
            .onChange(of: entries.count) { _ in
                if chatIsAtBottom { settleScroll(proxy) }
                ensurePreviousRequest(proxy)
            }
        }
    }

    @ViewBuilder
    func agentThreads(_ proxy: ScrollViewProxy) -> some View {
        if !childThreads.isEmpty {
            let open = agentThreadsAreOpen
            Button {
                agentThreadsExpanded.toggle()
                if agentThreadsExpanded { revealAgentThreads(proxy) }
            } label: {
                HStack(spacing: 7) {
                    Image(systemName: "point.3.connected.trianglepath.dotted")
                    Text(String(format: L("Agent conversations · %d"), childThreads.count))
                    Spacer()
                    Image(systemName: open ? "chevron.up" : "chevron.down")
                        .font(.system(size: 9, weight: .bold))
                }
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(open ? accent : Theme.muted)
                .padding(.top, rootEntries.isEmpty ? 0 : 6)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .id("agent-threads")
            .accessibilityLabel(String(format: L("Agent conversations · %d"), childThreads.count))

            if open {
                ForEach(childThreads) { row in
                    AgentThreadTranscript(
                        row: row,
                        entries: entries.filter { $0.childThreadId == row.thread.threadId },
                        accent: accent,
                        servers: currentSession.mcpServers ?? [],
                        onExpand: {
                            model.requestThreadEvents(chatSessionId, threadId: row.thread.threadId)
                        }
                    )
                    .padding(.leading, Self.threadIndent(row.visualDepth))
                    .id("thread:\(row.thread.threadId)")
                }
            }
        }
    }

    private var agentThreadsAreOpen: Bool {
        agentThreadsExpanded || childThreads.contains { row in
            entries.contains {
                $0.childThreadId == row.thread.threadId
                    && ($0.id == focusEntryId || $0.id == highlightedEntryId)
            }
        }
    }

    private var chatComposerInset: some View {
        VStack(spacing: 0) {
            ChatMessageQueueBar(session: currentSession).environmentObject(model)
            InChatApprovalsBar(sessionId: chatSessionId) { requestId in
                replyRequestId = requestId
                chatFocused = true
            }
            .environmentObject(model)
            composer
        }
    }

    @ToolbarContentBuilder
    private var chatToolbar: some ToolbarContent {
        ToolbarItemGroup(placement: .primaryAction) {
            if meshProjectId != nil {
                Button { openMesh() } label: {
                    Image(systemName: "point.3.connected.trianglepath.dotted")
                }
                .accessibilityLabel(L("Mesh"))
            }
            taskControlsMenu
        }
    }

    private var capabilitiesSheet: some View {
        ChatCapabilitySheet(
            sessionId: chatSessionId,
            session: currentSession,
            rows: capabilityRows,
            accent: accent,
            onToggle: toggleCapability
        ).environmentObject(model)
    }

    @ViewBuilder
    private var projectMeshSheet: some View {
        CompatNavigationStack {
            if let snapshot = projectMeshSnapshot {
                ProjectMeshView(snapshot: snapshot, model: model) { session in
                    model.sessionToOpen = session.sessionId
                    showProjectMesh = false
                }
            } else if let projectId = meshProjectId {
                ProjectMeshPendingView(
                    projectId: projectId, sessionId: chatSessionId, model: model
                )
            }
        }
    }

    func retryTranscript() {
        #if targetEnvironment(macCatalyst)
        if model.usesLocalMCP(for: currentSession) {
            Task { await loadLocalConversation() }
            return
        }
        #endif
        model.clearEmptyActivitySnapshot(sessionId: chatSessionId)
        model.relayForSession(chatSessionId)?.requestSessionEvents(sessionId: chatSessionId, history: true)
        model.subscribeSession(
            chatSessionId, active: true, source: "phone-chat:\(chatSessionId)"
        )
    }

    private func revealAgentThreads(_ proxy: ScrollViewProxy) {
        DispatchQueue.main.async {
            withAnimation(.easeOut(duration: 0.25)) {
                proxy.scrollTo("agent-threads", anchor: .top)
            }
        }
    }

    private func chatAppeared() {
        retainCurrentTranscript()
        model.subscribeSession(
            chatSessionId, active: true, source: "phone-chat:\(chatSessionId)"
        )
        if !model.demoMode {
            model.relayForSession(chatSessionId)?.requestSessionEvents(sessionId: chatSessionId, history: true)
        }
        Task { @MainActor in await focusComposerForDebugCapture() }
    }
    private func chatDisappeared() {
        model.releaseTranscriptHistory(sessionId: chatSessionId)
        let remainsLive = model.sessions.contains {
            model.resolvedSessionId($0.sessionId) == chatSessionId
        }
        model.subscribeSession(
            chatSessionId, active: false, source: "phone-chat:\(chatSessionId)",
            preserveRemoteSubscription: remainsLive
        )
    }
}
