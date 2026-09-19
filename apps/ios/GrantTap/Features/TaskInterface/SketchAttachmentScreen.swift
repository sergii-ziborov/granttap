import PencilKit
import SwiftUI
import UIKit

/// A white page the person draws on, then sends as a photo.
enum SketchAttachment {
    static func flattenedImage(from canvas: PKCanvasView) -> UIImage {
        let drawing = canvas.drawing
        let raw = drawing.bounds
        let renderRect: CGRect
        if raw.isNull || raw.isEmpty {
            let size = canvas.bounds.integral.size
            renderRect = CGRect(
                origin: .zero,
                size: CGSize(width: max(size.width, 320), height: max(size.height, 480))
            )
        } else {
            renderRect = raw.insetBy(dx: -28, dy: -28)
        }
        let sketch = drawing.image(from: renderRect, scale: UIScreen.main.scale)
        let renderer = UIGraphicsImageRenderer(size: sketch.size)
        return renderer.image { context in
            UIColor.white.setFill()
            context.fill(CGRect(origin: .zero, size: sketch.size))
            sketch.draw(at: .zero)
        }
    }
}

final class SketchCanvasBox: ObservableObject {
    let canvas = PKCanvasView()
}

struct SketchCanvasView: UIViewRepresentable {
    let canvas: PKCanvasView

    func makeUIView(context: Context) -> PKCanvasView {
        canvas.drawingPolicy = .anyInput
        canvas.backgroundColor = .white
        canvas.isOpaque = true
        canvas.overrideUserInterfaceStyle = .light
        canvas.tool = PKInkingTool(.pen, color: .black, width: 5)
        return canvas
    }

    func updateUIView(_ uiView: PKCanvasView, context: Context) {}
}

struct SketchAttachmentScreen: View {
    var onComplete: (UIImage) -> Void
    var onCancel: () -> Void
    @StateObject private var box = SketchCanvasBox()

    var body: some View {
        CompatNavigationStack {
            SketchCanvasView(canvas: box.canvas)
                .background(Color.white)
                .ignoresSafeArea(edges: .bottom)
                .navigationTitle(L("Sketch"))
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button(L("Cancel")) { onCancel() }
                    }
                    ToolbarItem(placement: .automatic) {
                        Button(L("Clear")) { box.canvas.drawing = PKDrawing() }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button(L("Use sketch")) {
                            onComplete(SketchAttachment.flattenedImage(from: box.canvas))
                        }
                        .accessibilityIdentifier("compose.sketch.use")
                    }
                }
        }
    }
}
