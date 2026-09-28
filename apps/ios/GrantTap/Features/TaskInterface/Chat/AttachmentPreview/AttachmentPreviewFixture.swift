#if DEBUG
import UIKit

enum AttachmentPreviewFixture {
    @MainActor static func applyScrollCapture(to model: AppModel, at now: Double) {
        guard ProcessInfo.processInfo.environment["GRANTTAP_TEST_ATTACHMENT_SCROLL"] == "1" else { return }
        let capture = scrollCapture(at: now)
        model.activities[AppModelDemoFixtures.codexSessionId] = capture.activity
        model.deliveries = [capture.delivery]
        model.pending = []
        model.questions = []
    }

    static var scrollDrafts: [AttachmentDraft] {
        drafts + (3...10).map {
            AttachmentDraft(name: "File-\($0).txt", mimeType: "text/plain",
                            data: Data("Attachment \($0)\n".utf8))
        }
    }

    static func scrollCapture(at now: Double) -> AppModelDemoFixtures.ChatCapture {
        let capture = AppModelDemoFixtures.chatCapture(at: now)
        var delivery = capture.delivery
        delivery.attachments = scrollDrafts.map(\.payload)
        let activity = SessionActivity(sessionId: delivery.sessionId ?? "", agent: "codex",
            state: "waiting", entries: [ActivityEntry(id: "local-user-\(delivery.id)", kind: "user",
                text: "Ten attached files", createdAt: delivery.createdAt,
                attachments: delivery.attachments.map(\.name))], generatedAt: now)
        return AppModelDemoFixtures.ChatCapture(activity: activity, delivery: delivery)
    }

    static var drafts: [AttachmentDraft] {
        let pdf = UIGraphicsPDFRenderer(bounds: CGRect(x: 0, y: 0, width: 300, height: 400))
            .pdfData { context in
                context.beginPage()
                ("PDF attachment fixture" as NSString).draw(at: CGPoint(x: 20, y: 20),
                    withAttributes: [.font: UIFont.systemFont(ofSize: 16)])
            }
        return [AttachmentDraft(name: "Fixture.swift", mimeType: "text/plain",
                    data: Data("let attachmentPreview = 42\n".utf8)),
                AttachmentDraft(name: "Fixture.pdf", mimeType: "application/pdf", data: pdf)]
    }
}
#endif
