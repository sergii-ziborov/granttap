import SwiftUI
import PhotosUI
import UniformTypeIdentifiers
import UIKit

extension TaskChatView {
    /// Nested agent conversations indent, but only so far: past four levels the
    /// text column becomes unreadable on a phone.
    static func threadIndent(_ visualDepth: Int) -> CGFloat {
        CGFloat(max(0, min(visualDepth - 1, 4))) * 16
    }

    /// Reads and writes this chat's own choice, so it survives closing the screen.
    var chatModelBinding: Binding<TurnModel?> {
        Binding(
            get: { model.turnOverrides.chatOverrides(chatSessionId).model },
            set: { picked in
                var current = model.turnOverrides.chatOverrides(chatSessionId)
                current.model = picked
                model.turnOverrides.setChatOverrides(current, for: chatSessionId)
            }
        )
    }

    var chatPermissionBinding: Binding<TurnPermissionMode?> {
        Binding(
            get: { model.turnOverrides.chatOverrides(chatSessionId).permissionMode },
            set: { picked in
                var current = model.turnOverrides.chatOverrides(chatSessionId)
                current.permissionMode = picked
                model.turnOverrides.setChatOverrides(current, for: chatSessionId)
            }
        )
    }

    func toggleCapability(_ row: ChatCapabilityRow) {
        switch row.kind {
        case .mcp:
            model.setSessionMcpAllowed(chatSessionId, serverName: row.name,
                                       allowed: row.allowed == false)
        case .skill:
            model.setSessionSkillAllowed(chatSessionId, skillName: row.name,
                                         allowed: row.allowed == false)
        case .cli:
            model.setSessionShellAllowed(chatSessionId, allowed: row.allowed == false)
        }
    }

    var timelineRows: [ChatTimelineRow] {
        ChatActivityGrouping.rows(combinedTimeline)
    }

    var pinnedUserLine: ChatScrollChrome.UserLine? {
        ChatScrollChrome.pinned(
            users: ChatScrollChrome.userLines(combinedTimeline),
            minYById: rowFrames.mapValues(\.minY),
            visibleIds: ChatScrollChrome.visibleIds(rowFrames, viewportHeight: scrollViewportHeight),
            orderedIds: timelineRows.map(\.id),
            top: 36
        )
    }

    var showJumpToLatest: Bool {
        guard let last = timelineRows.last else { return false }
        return ChatScrollChrome.showJumpToLatest(
            lastMaxY: rowFrames[last.id]?.maxY,
            viewportHeight: scrollViewportHeight
        )
    }

    func chatScroll(_ proxy: ScrollViewProxy) -> some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 14) {
                if combinedTimeline.isEmpty {
                    if !model.connected {
                        Text(L("Waiting for Mac connection to load messages…"))
                            .foregroundStyle(Theme.muted)
                    } else if loadTimedOut || activitySnapshotKnown {
                        VStack(alignment: .leading, spacing: 8) {
                            Text(L("No messages loaded for this chat yet."))
                                .foregroundStyle(Theme.muted)
                            Button(L("Retry")) {
                                loadTimedOut = false
                                model.clearEmptyActivitySnapshot(sessionId: chatSessionId)
                                model.subscribeSession(chatSessionId, active: true,
                                                       source: "phone-chat:\(chatSessionId)")
                                Task { @MainActor in
                                    try? await Task.sleep(nanoseconds: 4_000_000_000)
                                    if entries.isEmpty { loadTimedOut = true }
                                }
                            }
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(accent)
                        }
                    } else {
                        HStack(spacing: 8) {
                            ProgressView().controlSize(.small)
                            Text(L("Opening the encrypted chat…"))
                                .foregroundStyle(Theme.muted)
                        }
                    }
                } else {
                    ForEach(timelineRows) { row in
                        timelineRow(row)
                    }
                    if !childThreads.isEmpty {
                        // Folded like a run of CLI calls: one line says how
                        // many conversations there are, and opens to them.
                        // A conversation holding the entry someone tapped
                        // in history opens itself, or the tap would land
                        // on a closed summary of what it named.
                        let threadsOpen = agentThreadsExpanded || childThreads.contains { row in
                            entries.contains {
                                $0.childThreadId == row.thread.threadId
                                    && ($0.id == focusEntryId || $0.id == highlightedEntryId)
                            }
                        }
                        Button {
                            agentThreadsExpanded.toggle()
                            // The fold sits at the foot of the chat, so what it
                            // opens lands below the screen: bring the section up
                            // once it exists, or opening looks like nothing happened.
                            if agentThreadsExpanded {
                                DispatchQueue.main.async {
                                    withAnimation(.easeOut(duration: 0.25)) {
                                        proxy.scrollTo("agent-threads", anchor: .top)
                                    }
                                }
                            }
                        } label: {
                            HStack(spacing: 7) {
                                Image(systemName: "point.3.connected.trianglepath.dotted")
                                Text(String(format: L("Agent conversations · %d"), childThreads.count))
                                Spacer()
                                Image(systemName: threadsOpen ? "chevron.up" : "chevron.down")
                                    .font(.system(size: 9, weight: .bold))
                            }
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(threadsOpen ? accent : Theme.muted)
                            .padding(.top, rootEntries.isEmpty ? 0 : 6)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .id("agent-threads")
                        .accessibilityLabel(String(format: L("Agent conversations · %d"), childThreads.count))

                        if threadsOpen {
                            ForEach(childThreads) { row in
                                AgentThreadTranscript(
                                    row: row,
                                    entries: entries.filter {
                                        $0.childThreadId == row.thread.threadId
                                    },
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
                // No status card here: the mark now lives on the
                // message bubble, so repeating the text below the chat
                // showed every in-flight message twice.
                DeliveryStatusList(
                    deliveries: model.orphanDeliveries(for: chatSessionId)
                )
            }
            .padding(16)
        }
        .coordinateSpace(name: "chat-scroll")
        .background(
            GeometryReader { geo in
                Color.clear.preference(key: ChatViewportHeightKey.self, value: geo.size.height)
            }
        )
        .onPreferenceChange(ChatRowFrameKey.self) { rowFrames = $0 }
        .onPreferenceChange(ChatViewportHeightKey.self) { scrollViewportHeight = $0 }
        .onAppear { settleScroll(proxy) }
        .onChange(of: entries.count) { _ in settleScroll(proxy) }
    }

    var composer: some View {
        VStack(alignment: .leading, spacing: 7) {
            if let availability = chatSendAvailability {
                Text(availability.message)
                    .font(.system(size: 10.5, weight: .semibold))
                    .foregroundStyle(availability.blocksSending ? Theme.riskHigh : Theme.riskMed)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let attachmentError {
                Text(attachmentError)
                    .font(.system(size: 11.5, weight: .semibold))
                    .foregroundStyle(Theme.riskHigh)
            }
            MessageRoutingStrip(selectedMcp: $selectedMcp, selectedSkill: $selectedSkill)
            if dictator.isRecording || dictator.isStarting {
                ListeningStatus(isStarting: dictator.isStarting, language: dictator.detectedLanguage)
            }
            if let error = dictator.errorText {
                Text(error).font(.system(size: 11.5)).foregroundStyle(Theme.riskHigh)
            }
            // What was attached, what is being written, and how the turn will
            // run: one block, in that order.
            ComposerBlock {
                AttachmentThumbnails(attachments: $attachments)
                ComposerField(
                    placeholder: dictator.isRecording ? L("Listening…")
                        : (replyRequestId == nil ? L("Message this chat…") : L("Reply…")),
                    text: $draft, focus: $chatFocused, onSubmit: send
                )
                .onChange(of: dictator.transcript) { transcript in
                    if dictator.isRecording { draft = transcript }
                }
                HStack(spacing: 8) {
                    AttachmentMenuButton(attachments: $attachments,
                                         mcpServers: currentSession.mcpServers ?? [],
                                         skills: currentSession.skills ?? [],
                                         selectedMcp: $selectedMcp,
                                         selectedSkill: $selectedSkill)
                    ComposerModelPill(agent: currentSession.agent, model: chatModelBinding,
                                      current: currentSession.model)
                    Spacer(minLength: 4)
                    ListeningMicButton(isRecording: dictator.isRecording,
                                       isStarting: dictator.isStarting,
                                       tint: accent,
                                       action: toggleDictation)
                    let action = ComposerAction.resolve(
                        text: draft, attachments: attachments.count, isFocused: chatFocused
                    )
                    if action.isVisible {
                        ComposerSendButton(
                            action: action, tint: accent,
                            glyphInk: Theme.glyphInk(for: currentSession.agent),
                            blocked: chatSendAvailability?.blocksSending == true,
                            send: send,
                            dismissKeyboard: { chatFocused = false }
                        )
                    }
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.top, 10)
        // A picked attachment starts travelling at once, so the message that
        // follows has only to name it.
        .onChange(of: attachments.map(\.id)) { _ in
            model.preuploadAttachments(attachments, room: model.sourceRoom(forSessionId: chatSessionId))
        }
        // Matches the home composer: the safe-area inset is the bottom spacing.
        .padding(.bottom, 4)
        .background(currentSession.agent.lowercased().contains("claude")
                    ? Theme.claudeCanvas.opacity(0.97) : Theme.surface.opacity(0.97))
        .overlay(Rectangle().fill(Theme.line).frame(height: 1), alignment: .top)
    }

    /// Land on the entry the chat was opened for, once.
    ///
    /// The transcript keeps arriving after the view appears, so the focused
    /// entry may not exist yet on the first pass; the attempt repeats until it
    /// does. Afterwards the chat follows new activity as it always did, or the
    /// user would be dragged back to an old call by every incoming line.
    func settleScroll(_ proxy: ScrollViewProxy) {
        guard let focusEntryId, !focusHonoured else {
            followTranscript(proxy)
            return
        }
        guard let entry = entries.first(where: { $0.id == focusEntryId }) else { return }
        focusHonoured = true
        let target = ChatScrollTarget.forEntry(entry)
        DispatchQueue.main.async {
            withAnimation(.easeOut(duration: 0.2)) {
                proxy.scrollTo(target, anchor: .center)
                highlightedEntryId = focusEntryId
            }
        }
        // The mark is a pointer, not a selection: it fades once it has been seen,
        // leaving the transcript reading as it normally does.
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 2_600_000_000)
            withAnimation(.easeInOut(duration: 0.4)) { highlightedEntryId = nil }
        }
    }

    /// While older rows are still arriving, keep the person's last line where
    /// it is. Chasing every new count to the foot is what made that bubble
    /// fall down the chat during backfill.
    func followTranscript(_ proxy: ScrollViewProxy) {
        guard let target = ChatScrollTarget.followTarget(combinedTimeline) else { return }
        let liveFollow = combinedTimeline.last.map { $0.id == target } == true
        DispatchQueue.main.async {
            if liveFollow {
                withAnimation(.easeOut(duration: 0.2)) { proxy.scrollTo(target, anchor: .bottom) }
            } else {
                proxy.scrollTo(target, anchor: .bottom)
            }
        }
    }

    func scrollToBottom(_ proxy: ScrollViewProxy) {
        guard let last = combinedTimeline.last else {
            guard let lastEntry = entries.last else { return }
            let target = ChatScrollTarget.forEntry(lastEntry)
            DispatchQueue.main.async {
                withAnimation(.easeOut(duration: 0.2)) { proxy.scrollTo(target, anchor: .bottom) }
            }
            return
        }
        DispatchQueue.main.async {
            withAnimation(.easeOut(duration: 0.2)) { proxy.scrollTo(last.id, anchor: .bottom) }
        }
    }

    func toggleDictation() {
        if dictator.isRecording { draft = dictator.stop() }
        else { dictator.start() }
    }

    func send() {
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        if let requestId = replyRequestId {
            guard !text.isEmpty else { return }
            model.answerQuestion(requestId, text)
            replyRequestId = nil
            draft = ""
            attachments = []
            return
        }
        guard !text.isEmpty || !attachments.isEmpty else { return }
        guard chatSendAvailability?.blocksSending != true else { return }
        do {
            try AttachmentDraft.validateTotal(attachments)
            attachmentError = nil
        } catch {
            attachmentError = error.localizedDescription
            return
        }
        let room = model.sourceRoom(forSessionId: chatSessionId)
        model.sendMessage(text, agent: session.agent, sessionId: chatSessionId,
                          attachments: attachments.map(\.payload),
                          attachmentRefs: model.attachmentRefs(for: attachments, room: room),
                          preferredMcp: selectedMcp,
                          skill: selectedSkill,
                          overrides: model.turnOverrides.resolved(
                              sessionId: chatSessionId,
                              agent: currentSession.agent
                          ))
        draft = ""
        attachments = []
        attachmentError = nil
        selectedMcp = nil
        selectedSkill = nil
    }

    var chatSendAvailability: TaskSendAvailability? {
        if suppressAvailabilityForDebugCapture || model.demoMode { return nil }
        if currentSession.isPaused {
            return TaskSendAvailability(
                message: L("Paused from this phone: the computer refuses its tool calls. Resume to send."),
                blocksSending: true
            )
        }
        return TaskRoutePresentation.sendAvailability(
            agent: currentSession.agent,
            route: model.chatComputerRoute(forSessionId: chatSessionId)
        )
    }
}
