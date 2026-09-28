import SwiftUI

struct ChatFileReviewSheet: View {
    let file: RecordedFileChange
    let onClose: () -> Void

    var body: some View {
        CompatNavigationStack {
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .top, spacing: 12) {
                    Text(file.path).font(Theme.mono(12)).textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .accessibilityIdentifier("chat.review.path")
                    DiffStatsBadge(added: file.linesAdded, removed: file.linesRemoved)
                }
                .padding(.horizontal, 16).padding(.vertical, 12)
                if file.diffTruncated == true {
                    Text(L("This diff exceeds the preview limit."))
                        .font(.caption).foregroundStyle(Theme.muted)
                        .padding(.horizontal, 16).padding(.bottom, 8)
                }
                ChatFileDiffViewport {
                    DiffPreviewView(text: file.diff, wrapLines: false).textSelection(.enabled)
                }
                .id(file.id)
            }
            .foregroundStyle(Theme.ink)
            .background(Theme.bg)
            .navigationBarTitleDisplayMode(.inline)
            .pageNavigationTitle(URL(fileURLWithPath: file.path).lastPathComponent,
                showsBack: false, actionPlacement: .confirmationAction) {
                Button(L("Done"), action: onClose)
            }
        }
    }
}

struct ChatFileDiffViewport<Content: View>: View {
    @ViewBuilder let content: () -> Content

    var body: some View {
        GeometryReader { viewport in
            ScrollView(.vertical) {
                ScrollView(.horizontal) {
                    content()
                        .frame(minWidth: max(0, viewport.size.width - 32), alignment: .leading)
                        .padding(16)
                }
                .accessibilityIdentifier("chat.review.scroll")
            }
            .accessibilityIdentifier("chat.review.vertical")
        }
    }
}
