import SwiftUI
#if targetEnvironment(macCatalyst)
import UIKit
#endif

/// Sheet owners clear their presentation binding directly. The explicit action
/// remains valid when Catalyst rebuilds a nested navigation environment.
struct ChatSheetDoneButton: View {
    let identifier: String
    var title: String = L("Done")
    var dismissesPresentation = true
    let onClose: () -> Void

    var body: some View {
        #if targetEnvironment(macCatalyst)
        MacSheetCloseControl(identifier: identifier, title: title, dismissesPresentation: dismissesPresentation, onClose: onClose)
            .frame(width: 64, height: 36)
        #else
        Button(action: onClose) {
            Text(title)
                .font(.system(size: 14, weight: .semibold))
                .frame(minWidth: 56, minHeight: 36)
                .contentShape(Rectangle())
        }
        .pointerButtonStyle()
        .accessibilityIdentifier(identifier)
        .keyboardShortcut(.cancelAction)
        #endif
    }
}

#if targetEnvironment(macCatalyst)
/// Native Catalyst activation avoids SwiftUI's sheet-header hit-testing layer.
private struct MacSheetCloseControl: UIViewRepresentable {
    @Environment(\.isEnabled) private var isEnabled
    let identifier: String
    let title: String
    let dismissesPresentation: Bool
    let onClose: () -> Void

    func makeUIView(context: Context) -> UIButton {
        let button = UIButton(type: .system)
        button.titleLabel?.font = .systemFont(ofSize: 14, weight: .semibold)
        button.isPointerInteractionEnabled = true
        button.addTarget(context.coordinator, action: #selector(Coordinator.close(_:)), for: .primaryActionTriggered)
        return button
    }

    func updateUIView(_ button: UIButton, context: Context) {
        context.coordinator.onClose = onClose
        context.coordinator.dismissesPresentation = dismissesPresentation
        button.setTitle(title, for: .normal)
        button.isEnabled = isEnabled
        button.tintColor = UIColor(Theme.ink)
        button.accessibilityIdentifier = identifier
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(dismissesPresentation: dismissesPresentation, onClose: onClose)
    }

    final class Coordinator: NSObject {
        var onClose: () -> Void
        var dismissesPresentation: Bool
        init(dismissesPresentation: Bool, onClose: @escaping () -> Void) {
            self.dismissesPresentation = dismissesPresentation
            self.onClose = onClose
        }
        @objc func close(_ sender: UIButton) {
            guard dismissesPresentation else { onClose(); return }
            #if DEBUG
            if ProcessInfo.processInfo.environment["GRANTTAP_TEST_CHAT_WORK"] == "1" {
                print("GrantTap native Done activated")
            }
            #endif
            var responder: UIResponder? = sender
            while let current = responder {
                if let controller = current as? UIViewController,
                   controller.presentingViewController != nil {
                    controller.dismiss(animated: true, completion: onClose)
                    return
                }
                responder = current.next
            }
            onClose()
        }
    }
}
#endif
