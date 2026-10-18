import SwiftUI
import UIKit

/// Reject vertical intent before recognizing, so the parent keeps its pan.
struct TaskCardSwipeGesture: UIViewRepresentable {
    let onSwipe: (Bool) -> Void

    func makeUIView(context: Context) -> TaskCardSwipeView { TaskCardSwipeView() }
    func updateUIView(_ view: TaskCardSwipeView, context: Context) { view.onSwipe = onSwipe }
    static func dismantleUIView(_ view: TaskCardSwipeView, coordinator: ()) { view.detach() }
}

final class TaskCardSwipeView: UIView, UIGestureRecognizerDelegate {
    var onSwipe: ((Bool) -> Void)?
    private weak var scroll: UIScrollView?
    private lazy var pan: UIPanGestureRecognizer = {
        let recognizer = UIPanGestureRecognizer(target: self, action: #selector(swiped(_:)))
        recognizer.delegate = self
        recognizer.maximumNumberOfTouches = 1
        recognizer.delaysTouchesBegan = false
        return recognizer
    }()

    override init(frame: CGRect) { super.init(frame: frame); isUserInteractionEnabled = false }
    required init?(coder: NSCoder) { super.init(coder: coder); isUserInteractionEnabled = false }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        if window == nil { detach() }
        else { DispatchQueue.main.async { [weak self] in self?.attach() } }
    }

    override func layoutSubviews() { super.layoutSubviews(); attach() }

    private func attach() {
        guard window != nil else { return }
        var parent = superview
        while let candidate = parent {
            if let found = candidate as? UIScrollView {
                guard scroll !== found else { return }
                detach(); scroll = found; found.addGestureRecognizer(pan)
                return
            }
            parent = candidate.superview
        }
    }

    func detach() { scroll?.removeGestureRecognizer(pan); scroll = nil }

    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
        window != nil && bounds.contains(touch.location(in: self))
    }

    override func gestureRecognizerShouldBegin(_ recognizer: UIGestureRecognizer) -> Bool {
        guard let recognizer = recognizer as? UIPanGestureRecognizer else { return false }
        let velocity = recognizer.velocity(in: self)
        return velocity.x.isFinite && velocity.y.isFinite && abs(velocity.x) > 0
            && abs(velocity.x) > abs(velocity.y) * 1.3
    }

    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer,
                           shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool { true }

    @objc private func swiped(_ recognizer: UIPanGestureRecognizer) {
        guard recognizer.state == .ended else { return }
        let distance = recognizer.translation(in: self).x
        if abs(distance) > 32 { onSwipe?(distance < 0) }
    }
}
