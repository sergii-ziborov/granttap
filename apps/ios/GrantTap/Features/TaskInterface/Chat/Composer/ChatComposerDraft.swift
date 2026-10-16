import SwiftUI

/// Keystrokes belong to the composer, independently of a long transcript.
final class ChatComposerDraft: ObservableObject {
    @Published var text: String
    init(text: String = "") { self.text = text }
}

struct ChatComposerDraftScope<Content: View>: View {
    @ObservedObject var draft: ChatComposerDraft
    @ViewBuilder let content: () -> Content
    var body: some View { content() }
}
