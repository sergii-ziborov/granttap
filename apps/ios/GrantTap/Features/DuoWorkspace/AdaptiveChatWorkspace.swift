import SwiftUI

/// Keeps the same conversation and reply views alive as the device folds.
struct AdaptiveChatWorkspace<Conversation: View, Reply: View>: View {
    let conversation: Conversation
    let reply: Reply

    init(@ViewBuilder conversation: () -> Conversation, @ViewBuilder reply: () -> Reply) {
        self.conversation = conversation()
        self.reply = reply()
    }

    var body: some View {
        #if targetEnvironment(macCatalyst)
        standardWorkspace
        #else
        if #available(iOS 27.1, *) {
            FoldingChatWorkspace(conversation: conversation, reply: reply)
        } else {
            standardWorkspace
        }
        #endif
    }

    private var standardWorkspace: some View {
        conversation.safeAreaInset(edge: .bottom, spacing: 0) { reply }
    }
}

#if !targetEnvironment(macCatalyst)
@available(iOS 27.1, *)
private struct FoldingChatWorkspace<Conversation: View, Reply: View>: View {
    let conversation: Conversation
    let reply: Reply
    @State private var conversationFrame = CGRect.zero
    @State private var replyFrame = CGRect.zero

    var body: some View {
        ArrangementView {
            reply
                .background(frameReader(for: .reply))
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                .overlayArrangementEdge(VerticalEdge.bottom)
                .overlayArrangementEdge(HorizontalEdge.trailing)
        } secondary: {
            conversation
                .padding(.bottom, ChatSurfaceOcclusion.bottomInset(
                    conversation: conversationFrame, reply: replyFrame))
                .background(frameReader(for: .conversation))
        }
        .arrangementViewStyle(.overlay)
        .onPreferenceChange(ChatSurfaceFrames.self) { frames in
            if let frame = frames[.conversation] { conversationFrame = frame }
            if let frame = frames[.reply] { replyFrame = frame }
        }
    }

    private func frameReader(for surface: ChatSurface) -> some View {
        GeometryReader { geometry in
            Color.clear.preference(key: ChatSurfaceFrames.self,
                                   value: [surface: geometry.frame(in: .global)])
        }
    }
}

private enum ChatSurface: Hashable { case conversation, reply }

private struct ChatSurfaceFrames: PreferenceKey {
    static var defaultValue: [ChatSurface: CGRect] = [:]
    static func reduce(value: inout [ChatSurface: CGRect],
                       nextValue: () -> [ChatSurface: CGRect]) {
        value.merge(nextValue(), uniquingKeysWith: { _, latest in latest })
    }
}
#endif
