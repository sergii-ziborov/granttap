import SwiftUI
import UIKit

/// Native List recycling can remove its SwiftUI footer while it is at the end.
/// The actual scroll view remains the authority for reaching either edge.
struct TranscriptScrollPosition: UIViewRepresentable {
    let changed: (Bool) -> Void
    var scrolled: (() -> Void)? = nil

    func makeUIView(context: Context) -> ScrollProbe {
        let probe = ScrollProbe()
        probe.isUserInteractionEnabled = false
        probe.accessibilityElementsHidden = true
        return probe
    }
    func updateUIView(_ view: ScrollProbe, context: Context) {
        view.changed = changed
        view.scrolled = scrolled
        view.attach()
    }

    static func dismantleUIView(_ view: ScrollProbe, coordinator: ()) { view.detach() }

    final class ScrollProbe: UIView {
        var changed: ((Bool) -> Void)?
        var scrolled: (() -> Void)?
        private weak var scroll: UIScrollView?
        private var observations: [NSKeyValueObservation] = []
        private var reported: Bool?
        private var publishQueued = false

        override func didMoveToWindow() {
            super.didMoveToWindow()
            if window == nil {
                detach()
            } else { attach() }
        }

        func attach() {
            DispatchQueue.main.async { [weak self] in self?.findScroll() }
        }

        func detach() {
            scroll?.panGestureRecognizer.removeTarget(self, action: #selector(userScrolled(_:)))
            observations = []
            scroll = nil
        }

        private func findScroll() {
            guard window != nil else { return }
            var ancestor = superview
            while let parent = ancestor {
                if let found = nativeList(in: parent) {
                    guard scroll !== found else { publish(); return }
                    detach()
                    scroll = found
                    reported = nil
                    found.panGestureRecognizer.addTarget(self, action: #selector(userScrolled(_:)))
                    observations = [
                        found.observe(\.contentOffset, options: [.new]) { [weak self] _, _ in self?.queuePublish() },
                        found.observe(\.contentSize, options: [.new]) { [weak self] _, _ in self?.queuePublish() },
                        found.observe(\.bounds, options: [.new]) { [weak self] _, _ in self?.queuePublish() }
                    ]
                    publish()
                    return
                }
                ancestor = parent.superview
            }
        }

        @objc private func userScrolled(_ gesture: UIPanGestureRecognizer) {
            if gesture.state == .began || gesture.state == .changed { scrolled?() }
        }

        private func queuePublish() {
            guard !publishQueued else { return }
            publishQueued = true
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.publishQueued = false
                self.publish()
            }
        }

        private func nativeList(in view: UIView) -> UIScrollView? {
            if let list = view as? UICollectionView { return list }
            if let list = view as? UITableView { return list }
            for child in view.subviews {
                if let found = nativeList(in: child) { return found }
            }
            return nil
        }

        private func publish() {
            guard let scroll, scroll.bounds.height > 0, scroll.contentSize.height > 0 else { return }
            let remaining = scroll.contentSize.height + scroll.adjustedContentInset.bottom
                - scroll.contentOffset.y - scroll.bounds.height
            let atBottom = remaining <= 36
            guard reported != atBottom else { return }
            reported = atBottom
            changed?(atBottom)
        }
    }
}
