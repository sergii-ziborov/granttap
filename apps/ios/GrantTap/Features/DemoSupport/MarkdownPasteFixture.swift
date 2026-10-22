#if DEBUG
import UIKit

@MainActor
enum MarkdownPasteFixture {
    static let text = "# Review checklist\n\n- Queue receipts\n- Historical pictures\n\n```swift\nlet ready = true\n```\n"
    static func prepare() {
        let mode = ProcessInfo.processInfo.environment["GRANTTAP_TEST_MARKDOWN_PASTE"]
        guard ProcessInfo.processInfo.environment["GRANTTAP_DEMO"] == "1",
              mode == "1" || mode == "plain" else { return }
        UIPasteboard.general.string = mode == "plain" ? "Continue with the tests." : text
    }
}
#endif
