import PhotosUI
import SwiftUI
import UIKit
import XCTest
@testable import GrantTap

@MainActor
final class AttachmentCoverageTests: XCTestCase {
    func testAttachmentDraftValidationPayloadImageAndFormattingBoundaries() throws {
        let small = AttachmentDraft(
            name: "notes.txt", mimeType: "text/plain", data: Data("hello".utf8)
        )
        XCTAssertFalse(small.isImage)
        XCTAssertEqual(small.payload.name, "notes.txt")
        XCTAssertTrue(AttachmentDraft.canAppend(small, to: []))
        XCTAssertEqual(AttachmentDraft.totalBytes([small]), 5)
        XCTAssertNoThrow(try AttachmentDraft.validateTotal([small]))

        let oversized = AttachmentDraft(
            name: "large.bin", mimeType: "application/octet-stream",
            data: Data(count: AttachmentDraft.maxBytes + 1)
        )
        XCTAssertThrowsError(try AttachmentDraft.validateTotal([oversized]))
        XCTAssertFalse(AttachmentDraft.canAppend(
            small, to: Array(repeating: small, count: AttachmentDraft.maxCount)
        ))
        XCTAssertNil(AttachmentDraft.image(data: Data("bad".utf8), name: "bad.jpg"))
        let image = UIGraphicsImageRenderer(size: CGSize(width: 20, height: 10)).image { context in
            UIColor.systemBlue.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 20, height: 10))
        }
        let imageDraft = try XCTUnwrap(AttachmentDraft.image(
            data: image.pngData()!, name: "photo.png"
        ))
        XCTAssertTrue(imageDraft.isImage)
        XCTAssertEqual(imageDraft.mimeType, "image/jpeg")

        XCTAssertEqual(Format.tokens(0), "—")
        XCTAssertEqual(Format.tokens(999), "999")
        XCTAssertTrue(Format.tokens(1_000).contains("k"))
        XCTAssertTrue(Format.tokens(1_000_000).contains("M"))
        XCTAssertFalse(Format.duration(30).isEmpty)
        XCTAssertFalse(Format.duration(90).isEmpty)
        XCTAssertFalse(Format.duration(3_600).isEmpty)
        XCTAssertFalse(Format.duration(90_000).isEmpty)
        XCTAssertFalse(Format.latencyMs(500).isEmpty)
        XCTAssertFalse(Format.latencyMs(1_500).isEmpty)
    }

    func testAttachmentMenuAddsCameraLibraryAndImportedFilesWithinBounds() throws {
        var values: [AttachmentDraft] = []
        let binding = Binding<[AttachmentDraft]>(get: { values }, set: { values = $0 })
        let button = AttachmentMenuButton(attachments: binding)
        let image = UIGraphicsImageRenderer(size: CGSize(width: 24, height: 24)).image { context in
            UIColor.systemGreen.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 24, height: 24))
        }
        button.addLibraryImages([image, image])
        XCTAssertEqual(values.count, 2)
        button.addCameraImage(image)
        XCTAssertEqual(values.count, 3)

        let file = FileManager.default.temporaryDirectory
            .appendingPathComponent("granttap-attachment-\(UUID().uuidString).txt")
        defer { try? FileManager.default.removeItem(at: file) }
        try Data("fixture".utf8).write(to: file)
        button.importFiles(.success([file]))
        XCTAssertEqual(values.last?.name, file.lastPathComponent)
        button.importFiles(.failure(NSError(domain: "fixture", code: 1)))

        values = Array(repeating: values[0], count: AttachmentDraft.maxCount)
        button.addCameraImage(image)
        XCTAssertEqual(values.count, AttachmentDraft.maxCount)
        button.addLibraryImages([image])
        XCTAssertEqual(values.count, AttachmentDraft.maxCount)
        XCTAssertTrue(button.atAttachmentLimit)
        XCTAssertTrue(button.photoLibraryLabel.contains("0"))
        _ = button.cameraAvailable

        let oversizedFile = FileManager.default.temporaryDirectory
            .appendingPathComponent("oversized-\(UUID().uuidString).bin")
        defer { try? FileManager.default.removeItem(at: oversizedFile) }
        try Data(count: AttachmentDraft.maxBytes + 1).write(to: oversizedFile)
        values = []
        button.importFiles(.success([oversizedFile]))
        XCTAssertTrue(values.isEmpty)

        values = [AttachmentDraft(
            name: "budget.bin", mimeType: "application/octet-stream",
            data: Data(count: AttachmentDraft.maxTotalBytes - 10)
        )]
        button.addCameraImage(image)
        button.addLibraryImages([image])
        XCTAssertEqual(values.count, 1)

        let rich = AttachmentMenuButton(
            attachments: binding,
            mcpServers: [
                McpServerInfo(name: "github", configuredEnabled: true, allowed: true),
                McpServerInfo(name: "blocked", configuredEnabled: true, allowed: false),
            ],
            skills: [SkillInfo(name: "review", allowed: true)],
            selectedMcp: .constant("github"), selectedSkill: .constant("review")
        )
        XCTAssertEqual(rich.allowedMcpServers.map(\.name), ["github"])
        assertRendered(rich)
    }

    func testAttachmentMenuRoutesSelectionsCallbacksAndSecondaryPresentations() {
        var values: [AttachmentDraft] = []
        var selectedMcp: String? = "github"
        var selectedSkill: String? = "review"
        let attachments = Binding(get: { values }, set: { values = $0 })
        let mcp = Binding<String?>(get: { selectedMcp }, set: { selectedMcp = $0 })
        let skill = Binding<String?>(get: { selectedSkill }, set: { selectedSkill = $0 })
        let image = UIGraphicsImageRenderer(size: CGSize(width: 8, height: 8)).image { context in
            UIColor.orange.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 8, height: 8))
        }
        let button = AttachmentMenuButton(
            attachments: attachments,
            mcpServers: [McpServerInfo(name: "github", configuredEnabled: true, allowed: true)],
            skills: [SkillInfo(name: "review", allowed: true)],
            selectedMcp: mcp, selectedSkill: skill
        )
        button.chooseMcp(nil)
        button.chooseMcp("github")
        button.chooseSkill(nil)
        button.chooseSkill("review")
        button.completePhotoLibrary([image])
        button.cancelPhotoLibrary()
        button.completeCamera(image)
        button.cancelCamera()
        XCTAssertEqual(selectedMcp, "github")
        XCTAssertEqual(selectedSkill, "review")
        XCTAssertEqual(values.count, 2)

        assertRendered(AttachmentMenuButton(
            attachments: attachments, showPhotoLibrary: true
        ))
        assertRendered(AttachmentMenuButton(
            attachments: attachments, showCamera: true
        ))
        assertRendered(AttachmentMenuButton(
            attachments: attachments, errorText: "Fixture error"
        ))
    }

    func testCameraPickerCoordinatorReturnsImageFallbackAndCancel() {
        var images = 0
        var cancels = 0
        let picker = CameraAttachmentPicker(
            onImage: { _ in images += 1 }, onCancel: { cancels += 1 }
        )
        let coordinator = picker.makeCoordinator()
        let controller = UIImagePickerController()
        coordinator.imagePickerController(
            controller, didFinishPickingMediaWithInfo: [.originalImage: UIImage()]
        )
        coordinator.imagePickerController(controller, didFinishPickingMediaWithInfo: [:])
        coordinator.imagePickerControllerDidCancel(controller)
        XCTAssertEqual(images, 1)
        XCTAssertEqual(cancels, 2)
    }

    func testPhotoPickerCoordinatorCancelsAndReturnsLoadableImages() async {
        var cancelled = false
        let loaded = expectation(description: "photo loaded")
        var images: [UIImage] = []
        let picker = PhotoLibraryAttachmentPicker(
            maxSelectionCount: 2, onImages: { images = $0; loaded.fulfill() },
            onCancel: { cancelled = true }
        )
        let coordinator = picker.makeCoordinator()
        coordinator.picker(PHPickerViewController(configuration: PHPickerConfiguration()),
                           didFinishPicking: [])
        XCTAssertTrue(cancelled)
        let image = UIGraphicsImageRenderer(size: CGSize(width: 8, height: 8)).image { context in
            UIColor.red.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 8, height: 8))
        }
        coordinator.loadItemProviders([
            NSItemProvider(), NSItemProvider(object: image),
        ])
        await fulfillment(of: [loaded], timeout: 2)
        XCTAssertEqual(images.count, 1)
    }

    private func assertRendered<V: View>(_ view: V) {
        let frame = CGRect(x: 0, y: 0, width: 430, height: 932)
        let controller = UIHostingController(rootView: view)
        let window = UIWindow(frame: frame)
        window.rootViewController = controller
        window.isHidden = false
        controller.view.frame = frame
        controller.view.layoutIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.06))
        XCTAssertNotNil(controller.view.window)
        window.isHidden = true
    }
}
