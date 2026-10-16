import SwiftUI
import XCTest
@testable import GrantTap

@MainActor
final class EffortControlTests: XCTestCase {
    func testScaleUsesOnlySupportedLevelsAndKeepsUnknownDefaultUnknown() {
        for provider in AgentIdentity.composeIds {
            let choices = TurnEffort.supported(by: provider)
            let scale = EffortScale(choices: choices, selection: nil, fallback: nil)
            XCTAssertNil(scale.effective)
            for fraction in [-1.0, 0, 0.25, 0.6, 1, 2] {
                if choices.isEmpty { XCTAssertNil(scale.choice(at: fraction)) }
                else { XCTAssertTrue(choices.contains(scale.choice(at: fraction)!)) }
            }
            XCTAssertNil(scale.choice(at: .nan))
            XCTAssertNil(scale.choice(at: .infinity))
        }
        let restricted = EffortScale(choices: [.low, .high], selection: .ultra, fallback: .high)
        XCTAssertEqual(restricted.effective, .high)
        XCTAssertEqual(restricted.choice(at: 1), .high)
        XCTAssertEqual(restricted.fraction, 1)
        XCTAssertEqual(EffortScale(choices: [.high], selection: .high, fallback: nil).choice(at: 1), .high)
    }

    func testDraggingPersistsTheNativeLevelAndCarriesItIntoTheNextTurn() throws {
        let suite = "GrantTap.EffortControl.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = TurnOverrideStore(defaults: defaults)
        let selection = Binding<TurnEffort?>(get: { store.chatOverrides("task").effort }, set: {
            store.setChatOverrides(TurnOverrides(effort: $0), for: "task")
        })
        let parent = EffortSlider(scale: EffortScale(choices: TurnEffort.allCases,
            selection: nil, fallback: .medium), selection: selection)
        let coordinator = parent.makeCoordinator()
        let slider = EffortSliderControl()
        slider.maximumValue = 5
        slider.value = 3
        coordinator.changed(slider)
        XCTAssertEqual(selection.wrappedValue, .xhigh)
        slider.accessibilityIncrement()
        coordinator.changed(slider)
        XCTAssertEqual(selection.wrappedValue, .max)
        slider.accessibilityIncrement()
        slider.accessibilityIncrement()
        coordinator.changed(slider)
        let restored = TurnOverrideStore(defaults: defaults)
        XCTAssertEqual(restored.chatOverrides("task").wire(for: "codex").effort, "ultra")
        slider.accessibilityDecrement()
        coordinator.changed(slider)
        XCTAssertEqual(selection.wrappedValue, .max)
        slider.isEnabled = false
        slider.accessibilityDecrement()
        XCTAssertEqual(slider.value, 4)
    }

    func testEveryLevelAnimatesAndReducedMotionProducesAStaticFrame() {
        for effort in TurnEffort.allCases {
            let first = EffortMotion.particles(for: effort, time: 1, reduceMotion: false)
            XCTAssertNotEqual(first, EffortMotion.particles(for: effort, time: 2, reduceMotion: false))
            XCTAssertFalse(first.isEmpty)
            XCTAssertLessThanOrEqual(first.count, 48)
            XCTAssertTrue(first.allSatisfy { (0...1).contains($0.x) && (0...1).contains($0.y)
                && (0...1).contains($0.opacity) && $0.size > 0 })
            XCTAssertEqual(EffortMotion.particles(for: effort, time: 1, reduceMotion: true),
                           EffortMotion.particles(for: effort, time: 200, reduceMotion: true))
        }
    }
}
