import XCTest
import SwiftUI
@testable import GrantTap

@MainActor
final class ComposerDraftTests: XCTestCase {
    func testTypingUpdatesTheComposerWithoutRebuildingItsTranscriptOwner() {
        let draft = ChatComposerDraft(text: "Saved draft")
        let witness = ComposerRenderWitness()
        let host = UIHostingController(rootView: ComposerOwnerFixture(draft: draft, witness: witness))
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 640, height: 720))
        window.rootViewController = host
        window.isHidden = false
        host.view.layoutIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.1))
        defer { window.isHidden = true }
        let ownerRenders = witness.ownerRenders
        XCTAssertEqual(witness.visibleText, "Saved draft")
        draft.text = "New typed message"
        RunLoop.main.run(until: Date().addingTimeInterval(0.1))
        XCTAssertEqual(witness.visibleText, "New typed message")
        XCTAssertEqual(witness.ownerRenders, ownerRenders,
                       "Editing text must not invalidate the owner of thousands of transcript rows.")
    }
}

private final class ComposerRenderWitness {
    var ownerRenders = 0
    var visibleText = ""
}

private struct ComposerOwnerFixture: View {
    @State var draft: ChatComposerDraft
    let witness: ComposerRenderWitness

    var body: some View {
        let _ = witness.ownerRenders += 1
        ChatComposerDraftScope(draft: draft) {
            let _ = witness.visibleText = draft.text
            Text(draft.text)
        }
    }
}
