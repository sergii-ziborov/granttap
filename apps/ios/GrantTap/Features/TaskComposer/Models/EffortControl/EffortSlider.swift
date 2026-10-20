import SwiftUI
import UIKit

/// Native drag, click and accessibility control over the animated track.
struct EffortSlider: UIViewRepresentable {
    let scale: EffortScale
    @Binding var selection: TurnEffort?

    func makeUIView(context: Context) -> EffortSliderControl {
        let slider = EffortSliderControl()
        slider.semanticContentAttribute = .forceLeftToRight
        slider.minimumTrackTintColor = .clear
        slider.maximumTrackTintColor = .clear
        let thumb = UIGraphicsImageRenderer(size: CGSize(width: 38, height: 38)).image { image in
            image.cgContext.setShadow(offset: CGSize(width: 0, height: 1), blur: 3,
                                      color: UIColor.black.withAlphaComponent(0.18).cgColor)
            UIColor.white.setFill()
            UIBezierPath(ovalIn: CGRect(x: 4, y: 4, width: 30, height: 30)).fill()
        }
        slider.setThumbImage(thumb, for: .normal)
        slider.addTarget(context.coordinator, action: #selector(Coordinator.changed(_:)), for: .valueChanged)
        slider.accessibilityIdentifier = "composer.effort.slider"
        return slider
    }

    func updateUIView(_ slider: EffortSliderControl, context: Context) {
        context.coordinator.parent = self
        slider.minimumValue = 0
        slider.maximumValue = Float(max(1, scale.choices.count - 1))
        // Catalog or animation updates cannot take the thumb away from an active drag.
        if !slider.isTracking { slider.value = Float(scale.index ?? 0) }
        slider.isEnabled = scale.choices.count > 1
        slider.accessibilityLabel = L("Reasoning effort")
        if !slider.isTracking { slider.accessibilityValue = scale.effective?.label ?? L("Keep current effort") }
    }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject {
        var parent: EffortSlider
        init(_ parent: EffortSlider) { self.parent = parent }
        @objc func changed(_ slider: UISlider) {
            let value = Double(slider.value / max(1, slider.maximumValue))
            guard let choice = parent.scale.choice(at: value) else { return }
            if !slider.isTracking { slider.value = slider.value.rounded() }
            slider.accessibilityValue = choice.label
            if parent.selection != choice { parent.selection = choice }
        }
    }
}

final class EffortSliderControl: UISlider {
    override func didMoveToWindow() {
        super.didMoveToWindow()
        guard window != nil else { return }
        // A List normally waits before delivering touches to its content.
        // The slider must receive touch-down before a quick horizontal drag.
        var ancestor = superview
        while let view = ancestor {
            if let scroll = view as? UIScrollView {
                scroll.delaysContentTouches = false
                break
            }
            ancestor = view.superview
        }
    }

    override var canBecomeFirstResponder: Bool { true }
    override var keyCommands: [UIKeyCommand]? {
        [UIKeyCommand(input: UIKeyCommand.inputLeftArrow, modifierFlags: [], action: #selector(decrease)),
         UIKeyCommand(input: UIKeyCommand.inputRightArrow, modifierFlags: [], action: #selector(increase))]
    }
    override func beginTracking(_ touch: UITouch, with event: UIEvent?) -> Bool {
        becomeFirstResponder()
        return super.beginTracking(touch, with: event)
    }
    override func endTracking(_ touch: UITouch?, with event: UIEvent?) {
        super.endTracking(touch, with: event)
        settle()
    }
    override func cancelTracking(with event: UIEvent?) {
        super.cancelTracking(with: event)
        settle()
    }
    private func settle() {
        value = value.rounded()
        sendActions(for: .valueChanged)
    }
    override func accessibilityIncrement() { increase() }
    override func accessibilityDecrement() { decrease() }
    @objc private func increase() { step(1) }
    @objc private func decrease() { step(-1) }
    private func step(_ direction: Float) {
        guard isEnabled else { return }
        value = min(maximumValue, max(minimumValue, value.rounded() + direction))
        sendActions(for: .valueChanged)
    }
}
