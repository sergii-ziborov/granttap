import SwiftUI
import XCTest
@testable import GrantTap

/// The app explains itself, so what it says has to be there in both
/// languages and every page has to draw.
@MainActor
final class LearnSectionTests: XCTestCase {
    private var allTopics: [LearnTopic] { LearnChapter.all.flatMap(\.topics) }

    func testEveryChapterHasTopicsAndEveryTopicSaysSomething() {
        XCTAssertEqual(LearnChapter.all.count, 5)
        XCTAssertGreaterThanOrEqual(allTopics.count, 15)
        var ids = Set<String>()
        for topic in allTopics {
            XCTAssertTrue(ids.insert(topic.id).inserted, "two topics share the id \(topic.id)")
            XCTAssertFalse(topic.title.isEmpty)
            XCTAssertFalse(topic.summary.isEmpty)
            XCTAssertFalse(topic.icon.isEmpty)
            XCTAssertGreaterThanOrEqual(topic.body.count, 2, "\(topic.id) is a heading with no page")
            for block in topic.body {
                switch block {
                case .text(let value), .heading(let value), .command(let value):
                    XCTAssertFalse(value.isEmpty, topic.id)
                case .points(let items):
                    XCTAssertFalse(items.isEmpty, topic.id)
                    for item in items { XCTAssertFalse(item.isEmpty, topic.id) }
                }
            }
        }
    }

    /// Every word on these pages is asked for by name, so Russian readers get
    /// Russian rather than the key.
    func testEveryWordOfItIsTranslated() throws {
        let bundle = try XCTUnwrap(Bundle.main.path(forResource: "ru", ofType: "lproj")
            .flatMap(Bundle.init(path:)), "the Russian bundle is missing")
        var strings: [String] = ["Learn", "Nothing here matches that"]
        for chapter in LearnChapter.all {
            strings.append(chapter.title)
            for topic in chapter.topics {
                strings += [topic.title, topic.summary]
                for block in topic.body {
                    switch block {
                    case .text(let value), .heading(let value): strings.append(value)
                    case .points(let items): strings += items
                    case .command: break
                    }
                }
            }
        }
        let untranslated = strings.filter { bundle.localizedString(forKey: $0, value: "\u{0}", table: nil) == "\u{0}" }
        XCTAssertEqual(untranslated, [], "these have no Russian yet")
    }

    func testThePagesDraw() {
        RenderProbe.render(CompatNavigationStack { LearnView() }, height: 1_000)
        for topic in allTopics {
            RenderProbe.render(CompatNavigationStack { LearnTopicView(topic: topic) }, height: 1_400)
        }
    }
}
