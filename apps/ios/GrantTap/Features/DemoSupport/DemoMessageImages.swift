#if DEBUG
import UIKit

/// Deterministic image artifacts for the same gallery used by live MCP replies.
enum DemoMessageImages {
    static let attachments = (1...15).map { index in
        MessageImageAttachment(id: "demo-artifact-\(index)", name: "badge-\(index).png",
            markdown: "[badge-\(index).png](/workspace/artwork/badge-\(index).png)")
    }

    static func activity(at now: Double) -> SessionActivity {
        SessionActivity(sessionId: AppModelDemoFixtures.codexSessionId, agent: "codex", state: "idle",
            entries: [ActivityEntry(id: "artifact-reply", kind: "final",
                text: "Generated all 15 badges:\n\n" + attachments.map { "- \($0.markdown)" }.joined(separator: "\n"),
                createdAt: now, images: attachments)], generatedAt: now)
    }

    static func data(for id: String) -> Data? {
        guard ProcessInfo.processInfo.environment["GRANTTAP_TEST_ARTIFACT_IMAGES"] == "1",
              let index = attachments.firstIndex(where: { $0.id == id }) else { return nil }
        return imageData(index: index)
    }

    static func imageData(index: Int) -> Data {
        let image = UIGraphicsImageRenderer(size: CGSize(width: 300, height: 300)).image { _ in
            UIColor(hue: CGFloat(index) / 15, saturation: 0.65, brightness: 0.65, alpha: 1).setFill()
            UIRectFill(CGRect(x: 0, y: 0, width: 300, height: 300))
            UIColor.white.withAlphaComponent(0.9).setStroke()
            let circle = UIBezierPath(ovalIn: CGRect(x: 40, y: 40, width: 220, height: 220))
            circle.lineWidth = 6
            circle.stroke()
            let paragraph = NSMutableParagraphStyle()
            paragraph.alignment = .center
            ("\(index + 1)" as NSString).draw(in: CGRect(x: 40, y: 100, width: 220, height: 100),
                withAttributes: [.font: UIFont.systemFont(ofSize: 78, weight: .bold),
                                 .foregroundColor: UIColor.white, .paragraphStyle: paragraph])
        }
        return image.pngData()!
    }
}
#endif
