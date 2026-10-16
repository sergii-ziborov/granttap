#if DEBUG && targetEnvironment(macCatalyst)
import SwiftUI
import UIKit

/// Test-only timing from a sidebar action to the next display tick after layout.
/// It excludes XCTest's pointer movement, click delivery and polling overhead.
@MainActor
enum MacTabFrameTiming {
    static let enabled = ProcessInfo.processInfo.environment["GRANTTAP_TEST_TAB_FRAMES"] == "1"
    static var request: (tab: String, start: Double, generation: Int)?
    static var generation = 0
    static var lastValue = "idle"

    static func begin(_ tab: String) {
        guard enabled else { return }
        generation += 1
        request = (tab, ProcessInfo.processInfo.systemUptime, generation)
    }

    static func frame(_ tab: String) -> String {
        guard let request, request.tab == tab else { return lastValue }
        let elapsed = ProcessInfo.processInfo.systemUptime - request.start
        lastValue = "\(request.generation)|\(tab)|\(elapsed)"
        self.request = nil
        return lastValue
    }
}

struct MacTabFrameProbe: UIViewRepresentable {
    let tab: String
    func makeUIView(context: Context) -> TabFrameView { TabFrameView() }
    func updateUIView(_ view: TabFrameView, context: Context) {
        view.tab = tab
        view.setNeedsLayout()
    }

    final class TabFrameView: UIView {
        var tab = ""
        private var displayLink: CADisplayLink?
        init() {
            super.init(frame: .zero)
            isAccessibilityElement = true
            accessibilityIdentifier = "debug.tab-frame"
            accessibilityLabel = "Tab frame timing"
            accessibilityValue = MacTabFrameTiming.lastValue
        }
        required init?(coder: NSCoder) { nil }
        override func didMoveToWindow() {
            super.didMoveToWindow()
            if window == nil { displayLink?.invalidate(); displayLink = nil }
        }
        override func layoutSubviews() {
            super.layoutSubviews()
            guard window != nil, displayLink == nil else { return }
            let link = CADisplayLink(target: self, selector: #selector(framePresented))
            displayLink = link
            link.add(to: .main, forMode: .common)
        }
        @objc private func framePresented() {
            displayLink?.invalidate()
            displayLink = nil
            accessibilityValue = MacTabFrameTiming.frame(tab)
        }
    }
}
#endif
