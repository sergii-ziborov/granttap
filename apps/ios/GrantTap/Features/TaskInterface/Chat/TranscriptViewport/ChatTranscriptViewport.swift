import SwiftUI

/// Owns transcript layout independently of the full, durable message archive.
struct ChatTranscriptViewport<Content: View>: View {
    var canvas: Color = .clear
    var onBottomChanged: ((Bool) -> Void)? = nil
    var onUserScroll: (() -> Void)? = nil
    @ViewBuilder let content: () -> Content

    @ViewBuilder
    var body: some View {
        if #available(iOS 16.0, *) {
            list.scrollContentBackground(.hidden)
        } else {
            list
        }
    }

    private var list: some View {
        List {
            content()
                .listRowInsets(EdgeInsets(top: 7, leading: 16, bottom: 7, trailing: 16))
                .listRowSeparator(.hidden)
                .listRowBackground(canvas)
        }
        .listStyle(.plain)
        .environment(\.defaultMinListRowHeight, 1)
        .background(canvas)
        .background {
            if let onBottomChanged {
                TranscriptScrollPosition(changed: onBottomChanged, scrolled: onUserScroll)
            }
        }
    }
}
