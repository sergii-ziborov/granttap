import PDFKit
import SwiftUI

struct ReportDocumentPreview: View {
    let file: ReportPreviewFile

    var body: some View {
        if file.format == .pdf {
            ReportPDFPreview(file: file)
        } else {
            ReportCSVPreview(file: file)
        }
    }
}

private struct ReportPDFPreview: UIViewRepresentable {
    let file: ReportPreviewFile

    final class Coordinator { var url: URL? }
    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> PDFView {
        let view = PDFView()
        view.autoScales = true
        view.displayMode = .singlePageContinuous
        view.displayDirection = .vertical
        view.backgroundColor = .secondarySystemBackground
        view.accessibilityIdentifier = "report.preview.pdf"
        view.document = PDFDocument(data: file.data)
        context.coordinator.url = file.url
        return view
    }

    func updateUIView(_ view: PDFView, context: Context) {
        // File identity is stable while scrolling/zooming and while sharing.
        if context.coordinator.url != file.url {
            view.document = PDFDocument(data: file.data)
            context.coordinator.url = file.url
        }
    }
}

private struct ReportCSVPreview: UIViewRepresentable {
    let file: ReportPreviewFile

    final class Coordinator { var url: URL? }
    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> ReportCSVScrollView {
        let view = ReportCSVScrollView()
        view.show(file.csvText ?? "")
        context.coordinator.url = file.url
        return view
    }

    func updateUIView(_ view: ReportCSVScrollView, context: Context) {
        if context.coordinator.url != file.url {
            view.show(file.csvText ?? "")
            context.coordinator.url = file.url
        }
    }
}

/// A wide native text view inside a two-axis viewport. TextKit keeps full rows
/// even when UIKit updates the viewport bounds during sheet presentation.
final class ReportCSVScrollView: UIScrollView {
    let textView = UITextView()
    private var textWidth: CGFloat = 0

    override init(frame: CGRect) {
        super.init(frame: frame)
        accessibilityIdentifier = "report.preview.csv.scroll"
        alwaysBounceHorizontal = true
        alwaysBounceVertical = true
        textView.isEditable = false
        textView.isSelectable = true
        textView.isScrollEnabled = false
        textView.backgroundColor = .clear
        textView.font = .monospacedSystemFont(ofSize: 13, weight: .regular)
        textView.textColor = UIColor(Theme.ink)
        textView.textContainerInset = UIEdgeInsets(top: 16, left: 16, bottom: 16, right: 16)
        textView.accessibilityIdentifier = "report.preview.csv"
        addSubview(textView)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func show(_ text: String) {
        let font = textView.font ?? .monospacedSystemFont(ofSize: 13, weight: .regular)
        textWidth = text.components(separatedBy: .newlines).reduce(CGFloat(0)) {
            max($0, ($1 as NSString).size(withAttributes: [.font: font]).width.rounded(.up))
        } + 48
        textView.text = text
        setNeedsLayout()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let width = max(bounds.width, textWidth)
        let height = max(bounds.height, textView.sizeThatFits(
            CGSize(width: width, height: CGFloat.greatestFiniteMagnitude)).height)
        textView.frame = CGRect(x: 0, y: 0, width: width, height: height)
        let size = CGSize(width: width, height: height)
        if contentSize != size { contentSize = size }
    }
}
