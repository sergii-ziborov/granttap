#if targetEnvironment(macCatalyst)
import SwiftUI
import UIKit

/// Close the sheet that owns this view, including an outstanding confirmation.
/// Catalyst can leave its native sheet visible after only the SwiftUI binding clears.
struct ProjectTaskMacDismissal: UIViewRepresentable {
    let requested: Bool
    let onClosed: () -> Void

    func makeUIView(context: Context) -> UIView { UIView(frame: .zero) }
    func makeCoordinator() -> Coordinator { Coordinator() }

    func updateUIView(_ view: UIView, context: Context) {
        guard requested, !context.coordinator.closing else { return }
        context.coordinator.closing = true
        DispatchQueue.main.async {
            var responder: UIResponder? = view
            while let current = responder {
                if let controller = current as? UIViewController,
                   let presenter = controller.presentingViewController {
                    presenter.dismiss(animated: true, completion: onClosed)
                    return
                }
                responder = current.next
            }
            onClosed()
        }
    }

    final class Coordinator {
        var closing = false
    }
}
#endif
