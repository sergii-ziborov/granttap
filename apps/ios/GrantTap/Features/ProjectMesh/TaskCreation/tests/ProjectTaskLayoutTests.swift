#if targetEnvironment(macCatalyst)
import SwiftUI
import XCTest
@testable import GrantTap

@MainActor
final class ProjectTaskLayoutTests: XCTestCase {
    func testNewTaskKeepsABoundedFormInALargeMacWindow() {
        let model = AppModel()
        model.demoMode = true
        let snapshot = AppModelDemoMeshFixtures.snapshot(at: Date().timeIntervalSince1970 * 1_000)
        let host = UIHostingController(rootView: ProjectNewTaskView(snapshot: snapshot, model: model))
        let size = host.sizeThatFits(in: CGSize(width: 1400, height: 900))
        XCTAssertLessThanOrEqual(size.width, 820, "The task form must not grow across the Mac window.")
        XCTAssertLessThanOrEqual(size.height, 760, "Routing and Create must remain near the editor.")
    }
}
#endif
