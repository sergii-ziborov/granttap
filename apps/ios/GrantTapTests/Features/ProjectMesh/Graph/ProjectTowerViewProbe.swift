import SwiftUI
import UIKit

/// Mount real SwiftUI views; unit hosts cannot supply UI-test accessibility output.
@MainActor
enum ProjectTowerViewProbe {
    struct Snapshot {
        let size: CGSize
        let attachedToWindow: Bool
        let editorText: String?
    }

    static func render<V: View>(_ view: V, height: CGFloat = 1_400, query: String? = nil) -> Snapshot {
        let frame = CGRect(x: 0, y: 0, width: 430, height: height)
        let controller = UIHostingController(rootView: view)
        let window = UIWindow(frame: frame)
        window.rootViewController = controller
        window.isHidden = false
        defer { window.isHidden = true }
        controller.view.frame = frame
        settle(controller.view)
        let editor = textField(in: controller.view)
        if let query, let editor {
            editor.text = query
            editor.sendActions(for: .editingChanged)
            NotificationCenter.default.post(name: UITextField.textDidChangeNotification, object: editor)
        }
        settle(controller.view)
        return Snapshot(size: controller.view.bounds.size,
                        attachedToWindow: controller.view.window === window, editorText: editor?.text)
    }

    private static func settle(_ view: UIView) {
        view.setNeedsLayout()
        view.layoutIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.10))
        view.layoutIfNeeded()
    }

    private static func textField(in view: UIView) -> UITextField? {
        if let field = view as? UITextField { return field }
        return view.subviews.lazy.compactMap { textField(in: $0) }.first
    }
}
