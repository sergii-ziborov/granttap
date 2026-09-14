import XCTest
@testable import GrantTap

@MainActor
final class AttachmentUploadTests: XCTestCase {
    // The outbox persists across tests: a delivery left behind here would
    // surface as someone else's "needs you".
    override func setUp() {
        super.setUp()
        DeliveryPersistence.save([])
    }

    override func tearDown() {
        DeliveryPersistence.save([])
        super.tearDown()
    }

    private func draft(_ name: String) -> AttachmentDraft {
        AttachmentDraft(name: name, mimeType: "image/png", data: Data(repeating: 7, count: 32))
    }

    func testAPickedAttachmentGoesAheadAndTheMessageNamesIt() throws {
        let model = AppModel()
        let room = "upload-\(UUID().uuidString)"
        model.connectionRegistry = ConnectionRegistryLogic.upsert(.empty, pairing: PairingFixture.pairing(room: room))
        model.relaysByRoom[room] = RelayClient(pairing: PairingFixture.pairing(room: room))
        let photo = draft("photo.png")
        let doc = draft("notes.txt")

        model.preuploadAttachments([photo], room: nil)
        XCTAssertTrue(model.attachmentUploads.isEmpty, "nowhere to send it yet")
        model.preuploadAttachments([photo], room: room, now: 5)
        let upload = try XCTUnwrap(model.attachmentUploads[photo.id])
        XCTAssertEqual(upload.room, room)
        XCTAssertFalse(upload.accepted)
        XCTAssertEqual(upload.sentAt, 5)
        XCTAssertNotNil(upload.attachmentId.range(of: "^[a-z0-9-]+$", options: .regularExpression))
        model.preuploadAttachments([photo], room: room, now: 9)
        XCTAssertEqual(model.attachmentUploads[photo.id]?.sentAt, 5, "sent once")

        XCTAssertEqual(model.attachmentRefs(for: [photo], room: room), [], "not taken by the relay yet")
        model.attachmentUploads[photo.id]?.accepted = true
        let refs = model.attachmentRefs(for: [photo], room: room)
        XCTAssertEqual(refs.map(\.name), ["photo.png"])
        XCTAssertEqual(refs.first?.attachmentId, upload.attachmentId)
        XCTAssertEqual(model.attachmentRefs(for: [photo], room: "elsewhere"), [], "named only where it went")
        XCTAssertEqual(model.attachmentRefs(for: [photo, doc], room: room), [], "all by id or none, so the order holds")
        XCTAssertEqual(model.attachmentRefs(for: [photo], room: nil), [])
        model.forgetAttachmentUploads(for: [photo])
        XCTAssertTrue(model.attachmentUploads.isEmpty)

        let payload = Payloads.message("Look", messageId: "m", agent: "claude", cwd: nil, sessionId: "s", requestId: nil,
                                       attachments: [], attachmentRefs: refs)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: RelayClient.encodeOmittingNulls(payload)) as? [String: Any])
        XCTAssertNil(object["attachments"])
        XCTAssertEqual((object["attachmentRefs"] as? [[String: Any]])?.first?["name"] as? String, "photo.png")
        let uploadPayload = UserAttachmentUpload(type: "user.attachment", attachmentId: "a", name: "photo.png",
                                                 mimeType: "image/png", data: "AA==", createdAt: 1)
        let uploadObject = try XCTUnwrap(JSONSerialization.jsonObject(with: RelayClient.encodeOmittingNulls(uploadPayload)) as? [String: Any])
        XCTAssertEqual(uploadObject["type"] as? String, "user.attachment")
    }

    func testAMissingAttachmentIsSentAgainInline() throws {
        let model = AppModel()
        let room = "inline-\(UUID().uuidString)"
        model.connectionRegistry = ConnectionRegistryLogic.upsert(.empty, pairing: PairingFixture.pairing(room: room))
        let photo = draft("photo.png")
        let ref = UserAttachmentRef(attachmentId: "att-1", name: "photo.png", mimeType: "image/png")
        model.sendMessage("Look at this", agent: "claude", sessionId: nil, attachments: [photo.payload],
                          attachmentRefs: [ref], roomId: room)
        let delivery = try XCTUnwrap(model.deliveries.first { $0.text == "Look at this" })
        XCTAssertEqual(delivery.attachmentRefs, [ref])
        let named = model.wireUserMessage(for: delivery)
        XCTAssertEqual(named.attachmentRefs?.count, 1)
        XCTAssertNil(named.attachments, "named, so not carried")

        model.receive(DeliveryReceipt(type: "delivery.receipt", messageId: delivery.id, sessionId: nil,
                                      status: "rejected", error: AttachmentUploads.missingError, receivedAt: 2),
                      fromRoom: room)
        let resent = try XCTUnwrap(model.deliveries.first { $0.id == delivery.id })
        XCTAssertNil(resent.attachmentRefs, "the next attempt carries the bytes")
        let inline = model.wireUserMessage(for: resent)
        XCTAssertEqual(inline.attachments?.count, 1)
        XCTAssertNil(inline.attachmentRefs)
        XCTAssertTrue(model.log.contains { $0.contains("resent inline") })

        model.receive(DeliveryReceipt(type: "delivery.receipt", messageId: delivery.id, sessionId: nil,
                                      status: "rejected", error: "something else", receivedAt: 3), fromRoom: room)
        XCTAssertEqual(model.deliveries.first { $0.id == delivery.id }?.state, .failed, "any other rejection is final")
    }
}
