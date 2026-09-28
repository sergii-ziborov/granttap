import SwiftUI
import UIKit
import QuickLook
import XCTest
@testable import GrantTap

@MainActor
final class AttachmentPreviewTests: XCTestCase {
    func testFilesOfAnyExtensionRetainTheirOriginalBytesAndPayload() throws {
        var drafts: [AttachmentDraft] = []
        let picker = AttachmentMenuButton(attachments: Binding(get: { drafts }, set: { drafts = $0 }))
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: directory) }
        for name in ["Source.swift", "archive.zip", "unknown.custom", "no-extension", "empty.txt"] {
            let bytes = name == "empty.txt" ? Data() : Data([0, 1, 255, 10])
            let url = directory.appendingPathComponent(name)
            try bytes.write(to: url)
            picker.importFiles(.success([url]))
            XCTAssertEqual(drafts.last?.name, name)
            XCTAssertEqual(drafts.last?.data, bytes)
            XCTAssertEqual(drafts.last?.payload.data, bytes.base64EncodedString())
        }
        XCTAssertEqual(drafts.count, 5)
    }

    func testPreviewCopyKeepsSourceBytesAndCleansUpOnRelease() throws {
        let draft = AttachmentDraft(name: "Code.swift", mimeType: "text/plain", data: Data("let value = 1".utf8))
        var preview: AttachmentPreviewFile? = try AttachmentPreviewFile(draft)
        let directory = try XCTUnwrap(preview?.directory)
        let url = try XCTUnwrap(preview?.previewItemURL)
        XCTAssertEqual(preview?.text, "let value = 1")
        XCTAssertEqual(preview?.previewItemTitle, draft.name)
        XCTAssertEqual(try Data(contentsOf: url), draft.data)
        XCTAssertEqual(try FileManager.default.attributesOfItem(atPath: url.path)[.posixPermissions] as? Int, 0o600)
        XCTAssertEqual(try FileManager.default.attributesOfItem(atPath: directory.path)[.posixPermissions] as? Int, 0o700)
        preview = nil
        XCTAssertFalse(FileManager.default.fileExists(atPath: directory.path))
        XCTAssertEqual(draft.data, Data("let value = 1".utf8))
    }

    func testTextPDFAndUnsupportedBinaryUseTheAppropriatePreview() throws {
        for draft in AttachmentPreviewFixture.drafts + [AttachmentDraft(name: "data.unknown",
            mimeType: "application/octet-stream", data: Data([0, 255]))] {
            let file = try AttachmentPreviewFile(draft)
            if draft.name.hasSuffix(".swift") { XCTAssertNotNil(file.text) }
            else { XCTAssertNil(file.text) }
            if draft.name.hasSuffix(".pdf") {
                XCTAssertTrue(file.canPreview)
            }
            if file.text != nil || !file.canPreview {
                RenderProbe.render(AttachmentPreviewSheet(file: file, onClose: {}), height: 500)
            }
        }
    }

    #if targetEnvironment(macCatalyst)
    func testLocalBatchUsesPrivateNumericFilesAndDoesNotPutBytesOnTheSocket() throws {
        let files = AttachmentPreviewFixture.drafts
        let batch = try MacLocalAttachmentBatch(files)
        let directory = batch.directory
        defer { batch.remove() }
        let rows = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(batch.manifest.utf8)) as? [[String: String]])
        XCTAssertEqual(rows.map { $0["name"] }, files.map(\.name))
        for (index, row) in rows.enumerated() {
            let url = URL(fileURLWithPath: try XCTUnwrap(row["path"]))
            XCTAssertEqual(url.lastPathComponent, String(index))
            XCTAssertEqual(try Data(contentsOf: url), files[index].data)
            XCTAssertNil(row["data"])
        }
        batch.remove()
        XCTAssertFalse(FileManager.default.fileExists(atPath: directory.path))
    }
    #endif
}
