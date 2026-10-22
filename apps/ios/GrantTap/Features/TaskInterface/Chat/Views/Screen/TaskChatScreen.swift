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
        AdaptiveChatWorkspace {
            VStack(spacing: 0) {
                #if targetEnvironment(macCatalyst)
                macChatHeader
                #endif
                taskStatusStrip
                transferBanner
                chatTranscript
            }
        } reply: {
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
        .navigationTitle(ProjectMeshTaskTitle.presentable(currentSession.displayTitle)
                         ?? L("Untitled Task"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { chatToolbar }
        #endif
        .sheet(isPresented: $showSchedule) {
            ChatScheduleSheet(onClose: { showSchedule = false }, onSchedule: { queueDraft(at: $0) })
        }
        .sheet(isPresented: $showCapabilities) { capabilitiesSheet }
        .sheet(isPresented: $showHandoff) {
            TaskHandoffSheet(session: currentSession, model: model, onPrepared: openTransferredChat)
        }
        .sheet(isPresented: $showReport) {
            ReportExportSheet(report: model.report(for: reportScope), onClose: { showReport = false })
        }
        #if !targetEnvironment(macCatalyst)
        .sheet(isPresented: $showProjectMesh) { projectMeshSheet }
        #endif
        .onAppear(perform: chatAppeared)
        #if targetEnvironment(macCatalyst)
        .task(id: chatSessionId) {
            await loadLocalConversation()
            await model.refreshLocalTaskCapabilities(chatSessionId)
        }
        .task(id: chatSessionId) {
            while !Task.isCancelled {
                await model.refreshLocalTaskPreferences(chatSessionId)
                try? await Task.sleep(nanoseconds: 5_000_000_000)
            }
        }
        #endif
        .onDisappear(perform: chatDisappeared)
    }

    private var chatTranscript: some View {
        ScrollViewReader { proxy in
            VStack(spacing: 0) {
                latestUserMessageButton(proxy)
                GeometryReader { viewport in
                    ChatTranscriptViewport(canvas: Theme.canvas(for: currentSession.agent),
                        onBottomChanged: { atBottom in
                            chatIsAtBottom = atBottom
                            transcriptFitsViewport = atBottom && topVisibleTranscriptRow == timelineRows.first?.id
                        }, onUserScroll: {
                            if !historyAutoPagingReady { historyAutoPagingReady = true }
                        }) {
                        olderMessagesHeader(proxy)
                        transcriptRows(proxy, viewportHeight: viewport.size.height)
                        DeliveryStatusList(
                            deliveries: model.orphanDeliveries(for: chatSessionId)
                        )
                        Color.clear.frame(height: 56)
                            .id("chat-bottom")
                    }
                    .accessibilityIdentifier("chat.transcript")
                    .coordinateSpace(name: "chat-transcript")
                    .onPreferenceChange(ChatRowPositionKey.self) { positions in
                        guard let top = ChatPinnedUserMessage.topVisibleRow(
                            positions, viewportHeight: viewport.size.height
                        ) else { return }
                        updateTopTranscriptRow(top, proxy: proxy)
                        let first = positions.first { $0.id == timelineRows.first?.id }
                        if historyAutoPagingReady, let first, first.minY >= -100,
                           first.minY < viewport.size.height, !chatIsAtBottom, !historyError {
                            loadEarlierMessages(proxy)
                        }
                    }
                    .overlay(alignment: .bottomLeading) {
                        let work = ChatRequestWork(requestId: displayedRequestEntry?.id,
                            entries: transcriptPresentation.sourceEntries, threads: childThreads)
                        ChatActivityRail(model: model, session: currentSession,
                            entries: work.entries, threads: work.threads, recordedFiles: work.files,
                            requestId: displayedRequestEntry?.id, executionIds: taskExecutionSessionIds)
                            .padding(.bottom, 16)
                    }
                    .overlay(alignment: .bottomTrailing) {
                        if !chatIsAtBottom && !visibleTimeline.isEmpty {
                            jumpToLatestButton(proxy)
                                .padding(.bottom, 72)
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
        if !childThreads.isEmpty && agentThreadsAreOpen {
            let open = agentThreadsAreOpen
            Button {
                agentThreadsExpanded.toggle()
                if agentThreadsExpanded { revealAgentThreads(proxy) }
            } label: {
                HStack(spacing: 7) {
                    ChatAgentGlyph()
                    Text(String(format: L("Agents · %d"), childThreads.count))
                    Spacer()
                    Image(systemName: open ? "chevron.up" : "chevron.down")
                        .font(.system(size: 9, weight: .bold))
                }
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(open ? accent : Theme.muted)
                .padding(.top, rootEntries.isEmpty ? 0 : 6)
                .contentShape(Rectangle())
            }
            .pointerButtonStyle()
            .id("agent-threads")
            .accessibilityLabel(String(format: L("Agents · %d"), childThreads.count))

            if open {
                ForEach(childThreads) { row in
                    AgentThreadTranscript(
                        row: row,
                        entries: entries.filter { $0.childThreadId == row.thread.threadId },
                        accent: accent,
                        servers: currentSession.mcpServers ?? [],
                        onExpand: {
                            model.requestThreadEvents(row.executionSessionId ?? chatSessionId,
                                                      threadId: row.thread.threadId)
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
            onClose: { showCapabilities = false },
            onPrepared: openTransferredChat,
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
        model.recoverSavedChatQueueReceipts(for: currentSession)
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
