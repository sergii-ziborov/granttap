import SwiftUI
import XCTest
@testable import GrantTap

/// The message and the way it will be sent are one block, and a person's
/// message does not look like the agent's answer.
@MainActor
final class ComposerShapeTests: XCTestCase {
    private func draft(_ name: String, mime: String, bytes: Data) -> AttachmentDraft {
        AttachmentDraft(name: name, mimeType: mime, data: bytes)
    }

    private func imageData() -> Data {
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: 8, height: 8))
        return renderer.image { context in
            UIColor.systemOrange.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 8, height: 8))
        }.pngData() ?? Data()
    }

    func testWhatIsAttachedIsShownAsItselfAndCanBeTakenBack() {
        var attachments = [
            draft("shot.png", mime: "image/png", bytes: imageData()),
            draft("notes.txt", mime: "text/plain", bytes: Data("hello".utf8)),
        ]
        let binding = Binding(get: { attachments }, set: { attachments = $0 })
        RenderProbe.render(AttachmentThumbnails(attachments: binding), height: 120)
        // The strip is empty when nothing is attached, not a blank band.
        var none: [AttachmentDraft] = []
        RenderProbe.render(AttachmentThumbnails(attachments: Binding(get: { none }, set: { none = $0 })), height: 120)
        XCTAssertEqual(attachments.count, 2)
        attachments.removeAll { $0.name == "notes.txt" }
        XCTAssertEqual(attachments.map(\.name), ["shot.png"])
    }

    func testTheModelPillNamesTheChoiceAndTheSendButtonSaysWhatItWillDo() {
        var picked: TurnModel? = nil
        let binding = Binding(get: { picked }, set: { picked = $0 })
        RenderProbe.render(ComposerModelPill(agent: "claude", model: binding), height: 60)
        picked = TurnModel.supported(by: "claude").first
        RenderProbe.render(ComposerModelPill(agent: "claude", model: binding), height: 60)
        XCTAssertNotNil(picked)
        // An agent nobody has models for still draws, saying the agent's name.
        RenderProbe.render(ComposerModelPill(agent: "grok_bot", model: .constant(nil)), height: 60)

        for action in [ComposerAction.send, .dismiss] {
            RenderProbe.render(
                ComposerSendButton(action: action, tint: Theme.claude, glyphInk: .black,
                                   blocked: action == .send, send: {}, dismissKeyboard: {}),
                height: 60
            )
        }
    }

    func testAPersonsMessageAndAnAgentsAnswerAreDrawnDifferently() {
        let model = AppModel()
        let mine = ActivityEntry(id: "e-user", kind: "user", text: "Ship it", createdAt: 1)
        let theirs = ActivityEntry(id: "e-agent", kind: "final", text: "Shipped it", createdAt: 2)
        RenderProbe.render(ActivityRow(entry: mine, accent: Theme.claude, compact: false).environmentObject(model))
        RenderProbe.render(ActivityRow(entry: theirs, accent: Theme.claude, compact: false).environmentObject(model))
        // Compact rows are one list line each: a person's message is not a
        // block there, or the task list would grow bubbles.
        RenderProbe.render(ActivityRow(entry: mine, accent: Theme.claude, compact: true).environmentObject(model))
    }

    /// A photo this phone still holds is shown as the photo, with the delivery
    /// mark on the message that carried it; one known only by name is not.
    func testAMessageShowsThePictureItCarriedAndHowItWentOut() throws {
        let model = AppModel()
        let png = imageData()
        model.deliveries = [OutgoingDelivery(
            id: "d-1", text: "Look at this", agent: "claude", cwd: "/repo",
            sessionId: "s", requestId: nil, roomId: "room",
            attachments: [UserAttachment(name: "shot.png", mimeType: "image/png",
                                         data: png.base64EncodedString())],
            preferredMcp: nil, skill: nil, createdAt: 1, updatedAt: 2,
            attempts: 1, state: .delivered, error: nil, nextRetryAt: nil
        )]
        var carried = ActivityEntry(id: "local-user-d-1", kind: "user",
                                    text: "Look at this", createdAt: 3)
        carried.attachments = ["shot.png"]
        XCTAssertNotNil(model.sentAttachmentImage(forEntryId: carried.id, name: "shot.png"))
        XCTAssertNotNil(model.deliveryTick(forEntryId: carried.id))
        RenderProbe.render(ActivityRow(entry: carried, accent: Theme.claude, compact: false)
            .environmentObject(model), height: 700)

        // A transcript names a file this phone never held: a name, not a frame.
        var named = ActivityEntry(id: "e-remote", kind: "user", text: "", createdAt: 4)
        named.attachments = ["from-the-mac.pdf"]
        XCTAssertNil(model.sentAttachmentImage(forEntryId: named.id, name: "from-the-mac.pdf"))
        RenderProbe.render(ActivityRow(entry: named, accent: Theme.claude, compact: false)
            .environmentObject(model), height: 700)
    }
}
