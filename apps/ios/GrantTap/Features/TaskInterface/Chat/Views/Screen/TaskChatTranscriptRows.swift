import SwiftUI

extension TaskChatView {
    @ViewBuilder
    func transcriptRows(_ proxy: ScrollViewProxy) -> some View {
        let phase = ChatTranscriptPhase.resolve(
            hasContent: !visibleTimeline.isEmpty,
            connected: model.connected,
            snapshotKnown: activitySnapshotKnown
        )
        if phase == .content {
            ForEach(ChatActivityGrouping.rows(visibleTimeline)) { row in
                timelineRow(row)
                    .background(GeometryReader { geometry in
                        let frame = geometry.frame(in: .named("chat-transcript"))
                        Color.clear.preference(
                            key: ChatRowPositionKey.self,
                            value: [ChatRowPosition(id: row.id, minY: frame.minY, maxY: frame.maxY)]
                        )
                    })
            }
            agentThreads(proxy)
        } else if phase == .disconnected {
            #if targetEnvironment(macCatalyst)
            if model.usesLocalMCP(for: currentSession) {
                if localActivityError {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(L("Could not load this Task's messages from this Mac."))
                            .foregroundStyle(Theme.muted)
                        Button(L("Retry"), action: retryTranscript)
                    }
                } else if localActivityLoading {
                    ProgressView(L("Loading messages from this Mac…"))
                } else {
                    Button(L("Load messages"), action: retryTranscript)
                }
            } else {
                Text(L("Waiting for Mac connection to load messages…"))
                    .foregroundStyle(Theme.muted)
            }
            #else
            Text(L("Waiting for Mac connection to load messages…"))
                .foregroundStyle(Theme.muted)
            #endif
        } else if phase == .empty {
            VStack(alignment: .leading, spacing: 8) {
                Text(L("No messages loaded for this chat yet."))
                    .foregroundStyle(Theme.muted)
                Button(L("Retry"), action: retryTranscript)
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
    }

}
