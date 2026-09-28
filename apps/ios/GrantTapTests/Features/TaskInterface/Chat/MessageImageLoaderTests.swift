import XCTest
import SwiftUI
@testable import GrantTap

@MainActor
final class MessageImageLoaderTests: XCTestCase {
    func testImageBytesDecodeAllFifteenPreviewsAndDoNotReloadLoadedImages() async {
        let loader = MessageImageLoader()
        var calls = 0
        await loader.load(DemoMessageImages.attachments) { attachment in
            calls += 1
            return DemoMessageImages.imageData(index: Int(attachment.name.dropFirst(6).dropLast(4))! - 1)
        }
        XCTAssertEqual(loader.images.count, 15)
        XCTAssertTrue(loader.failed.isEmpty)
        XCTAssertEqual(calls, 15)
        await loader.load(DemoMessageImages.attachments) { _ in calls += 1; return Data() }
        XCTAssertEqual(calls, 15)
        XCTAssertEqual(loader.images.values.first?.size.width, loader.images.values.first?.size.height)
        XCTAssertGreaterThan(loader.images.values.first?.size.width ?? 0, 0)
    }

    func testUnavailableOrInvalidPictureCanBeRetriedWithoutDroppingOtherImages() async {
        let loader = MessageImageLoader()
        let images = Array(DemoMessageImages.attachments.prefix(3))
        await loader.load(images) { image in
            if image.id == images[0].id { throw MessageImageLoader.ImageError.unavailable }
            return image.id == images[1].id ? Data("bad".utf8) : DemoMessageImages.imageData(index: 2)
        }
        XCTAssertEqual(loader.failed, Set(images.prefix(2).map(\.id)))
        XCTAssertNotNil(loader.images[images[2].id])
        await loader.load(images) { _ in DemoMessageImages.imageData(index: 1) }
        XCTAssertEqual(loader.images.count, 3)
        XCTAssertTrue(loader.failed.isEmpty)
        XCTAssertNil(MessageImageLoader.thumbnail(Data()))
        XCTAssertNil(MessageImageLoader.thumbnail(Data(repeating: 0, count: 8 * 1_024 * 1_024 + 1)))
    }

    func testGalleryPreservesImageMetadataThroughWireAndRender() throws {
        let entry = DemoMessageImages.activity(at: 1).entries[0]
        let data = try JSONEncoder().encode(entry)
        XCTAssertEqual(try JSONDecoder().decode(ActivityEntry.self, from: data), entry)
        RenderProbe.render(MessageImageContentView(entry: entry, compact: false)
            .environmentObject(AppModel()))
        RenderProbe.render(MessageImageContentView(entry: entry, compact: true)
            .environmentObject(AppModel()))
        RenderProbe.render(MessageImageGallery(images: Array(DemoMessageImages.attachments.prefix(2)),
            load: { _ in DemoMessageImages.imageData(index: 0) }))
    }
}
