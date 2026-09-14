import SwiftUI
import UIKit

/// Lay a view out the way the repository's other coverage tests do.
///
/// A UIHostingController with a frame is not enough: SwiftUI does not evaluate
/// a body until the view is in a window and the run loop has turned, so a test
/// that only sets a frame renders nothing and covers nothing while appearing
/// to exercise the screen.
@MainActor
enum RenderProbe {
    static func render<V: View>(_ view: V, height: CGFloat = 932) {
        let frame = CGRect(x: 0, y: 0, width: 430, height: height)
        let controller = UIHostingController(rootView: view)
        let window = UIWindow(frame: frame)
        window.rootViewController = controller
        window.isHidden = false
        controller.view.frame = frame
        controller.view.setNeedsLayout()
        controller.view.layoutIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.06))
    }
}
