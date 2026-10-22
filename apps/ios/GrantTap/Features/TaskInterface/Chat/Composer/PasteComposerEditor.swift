import SwiftUI
import UIKit

/// Intercepts the explicit system Paste action before a large document enters
/// SwiftUI's text binding. Typing, dictation and ordinary short paste stay text.
struct PasteComposerEditor: UIViewRepresentable {
    @Binding var text: String
    var focus: Binding<Bool>
    let placeholder: String
    var minimumHeight: CGFloat = 22
    var maximumHeight: CGFloat = 132
    var submitsOnReturn = true
    var identifier = "composer.message"
    let onSubmit: () -> Void
    let onPaste: (String) -> Bool
    @Binding var height: CGFloat

    func makeUIView(context: Context) -> PasteComposerTextView {
        let view = PasteComposerTextView()
        view.delegate = context.coordinator
        view.backgroundColor = .clear
        view.font = .systemFont(ofSize: 16)
        view.textColor = UIColor(Theme.ink)
        view.textContainerInset = .zero
        view.textContainer.lineFragmentPadding = 0
        view.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        return view
    }

    func updateUIView(_ view: PasteComposerTextView, context: Context) {
        context.coordinator.parent = self
        view.accessibilityIdentifier = identifier
        view.accessibilityLabel = placeholder
        view.returnKeyType = submitsOnReturn ? .send : .default
        view.textColor = UIColor(Theme.ink)
        view.onPaste = onPaste
        view.onLayout = { [weak coordinator = context.coordinator] in coordinator?.measure() }
        if view.text != text {
            let selection = view.selectedRange
            view.text = text
            view.selectedRange = NSRange(location: min(selection.location, text.utf16.count), length: 0)
        }
        context.coordinator.view = view
        if focus.wrappedValue != view.isFirstResponder {
            DispatchQueue.main.async { [weak view, weak coordinator = context.coordinator] in
                guard let view, let coordinator else { return }
                if coordinator.parent.focus.wrappedValue { view.becomeFirstResponder() }
                else { view.resignFirstResponder() }
            }
        }
        context.coordinator.measure()
    }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject, UITextViewDelegate {
        var parent: PasteComposerEditor
        weak var view: PasteComposerTextView?
        init(_ parent: PasteComposerEditor) { self.parent = parent }

        func textViewDidChange(_ textView: UITextView) {
            parent.text = textView.text
            measure()
        }
        func textViewDidBeginEditing(_ textView: UITextView) { parent.focus.wrappedValue = true }
        func textViewDidEndEditing(_ textView: UITextView) { parent.focus.wrappedValue = false }
        func textView(_ textView: UITextView, shouldChangeTextIn range: NSRange,
                      replacementText text: String) -> Bool {
            if text == "\n", parent.submitsOnReturn { parent.onSubmit(); return false }
            return true
        }
        func measure() {
            guard let view, view.bounds.width > 0 else { return }
            let natural = view.sizeThatFits(CGSize(width: view.bounds.width, height: .greatestFiniteMagnitude)).height
            let measured = min(parent.maximumHeight, max(parent.minimumHeight, ceil(natural)))
            view.isScrollEnabled = natural > parent.maximumHeight
            guard abs(parent.height - measured) > 0.5 else { return }
            DispatchQueue.main.async { [weak self] in self?.parent.height = measured }
        }
    }
}

final class PasteComposerTextView: UITextView {
    var onPaste: ((String) -> Bool)?
    var onLayout: (() -> Void)?
    override func layoutSubviews() { super.layoutSubviews(); onLayout?() }
    override func paste(_ sender: Any?) {
        if let text = UIPasteboard.general.string, onPaste?(text) == true { return }
        super.paste(sender)
    }
}
