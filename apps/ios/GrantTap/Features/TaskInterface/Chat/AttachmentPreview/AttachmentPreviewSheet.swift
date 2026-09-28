import SwiftUI
import QuickLook

struct AttachmentPreviewSheet: View {
    let file: AttachmentPreviewFile
    let onClose: () -> Void

    var body: some View {
        CompatNavigationStack {
            VStack(spacing: 0) {
                HStack {
                    Text(file.name).lineLimit(2).textSelection(.enabled)
                    Spacer()
                    Text(ByteCountFormatter.string(fromByteCount: Int64(file.data.count), countStyle: .file))
                        .foregroundStyle(Theme.muted)
                }
                .font(.caption).padding(12)
                if let text = file.text {
                    AttachmentTextPreview(text: text)
                        .accessibilityIdentifier("attachment.preview.text")
                } else {
                    Spacer()
                    Label(L("Preview is not available for this file type."), systemImage: "doc")
                        .foregroundStyle(Theme.muted).padding()
                    Spacer()
                }
            }
            .background(Theme.bg)
            .navigationBarTitleDisplayMode(.inline)
            .pageNavigationTitle(file.name, showsBack: false, actionPlacement: .confirmationAction) {
                Button(L("Done"), action: onClose)
            }
        }
    }
}

struct AttachmentTextPreview: UIViewRepresentable {
    let text: String
    func makeUIView(context: Context) -> UITextView {
        let view = UITextView()
        view.isEditable = false
        view.isSelectable = true
        view.font = .monospacedSystemFont(ofSize: 13, weight: .regular)
        view.backgroundColor = .clear
        view.textContainerInset = UIEdgeInsets(top: 8, left: 12, bottom: 12, right: 12)
        return view
    }
    func updateUIView(_ view: UITextView, context: Context) { view.text = text }
}

/// Present Quick Look natively: embedding its controller on Mac only produces a thumbnail.
struct AttachmentPreviewPresentation: ViewModifier {
    @Binding var file: AttachmentPreviewFile?
    private var usesQuickLook: Bool { file?.text == nil && file?.canPreview == true }

    func body(content: Content) -> some View {
        content
            .sheet(isPresented: Binding(
                get: { file != nil && !usesQuickLook },
                set: { if !$0 { file = nil } }
            )) {
                if let file { AttachmentPreviewSheet(file: file) { self.file = nil } }
            }
            .quickLookPreview(Binding(
                get: { usesQuickLook ? file?.url : nil },
                set: { if $0 == nil && usesQuickLook { file = nil } }
            ))
    }
}
