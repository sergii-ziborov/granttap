import SwiftUI

/// Full-screen look at a photo you sent: pinch to zoom, drag while zoomed, tap
/// or the close button to dismiss.
struct ImagePreviewScreen: View {
    let image: UIImage
    let onClose: () -> Void

    @State private var scale: CGFloat = 1
    @State private var offset: CGSize = .zero

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            Image(uiImage: image)
                .resizable()
                .scaledToFit()
                .scaleEffect(scale)
                .offset(offset)
                .gesture(
                    MagnificationGesture()
                        .onChanged { scale = max(1, $0) }
                        .onEnded { _ in if scale < 1.05 { withAnimation { scale = 1; offset = .zero } } }
                )
                .gesture(
                    DragGesture()
                        .onChanged { if scale > 1 { offset = $0.translation } }
                        .onEnded { _ in if scale <= 1 { withAnimation { offset = .zero } } }
                )
                .onTapGesture { onClose() }
        }
        .overlay(alignment: .topTrailing) {
            Button(action: onClose) {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 28))
                    .foregroundStyle(.white.opacity(0.85))
                    .padding()
            }
            .accessibilityLabel(L("Close"))
        }
    }
}
