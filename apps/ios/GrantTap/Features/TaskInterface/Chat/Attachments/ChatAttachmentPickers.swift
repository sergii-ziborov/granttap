import SwiftUI
import PhotosUI
import UniformTypeIdentifiers
import UIKit

struct AttachmentDraft: Identifiable {
    static let maxCount = 10
    static let maxBytes = 6_000_000
    /// The relay protocol allows 16M base64 characters for encoded
    /// attachments. 11MB raw leaves room for base64 expansion, JSON metadata,
    /// and the encrypted envelope while remaining below that frame budget.
    static let maxTotalBytes = 11_000_000
    let id = UUID()
    let name: String
    let mimeType: String
    let data: Data

    var isImage: Bool { mimeType.hasPrefix("image/") }
    var payload: UserAttachment {
        UserAttachment(name: name, mimeType: mimeType, data: data.base64EncodedString())
    }

    enum Error: LocalizedError {
        case tooLarge(String)
        case totalTooLarge
        var errorDescription: String? {
            switch self {
            case .tooLarge(let name):
                return String(format: L("%@ is larger than 6 MB."), name)
            case .totalTooLarge:
                return L("Attachments exceed the 11 MB total limit.")
            }
        }
    }

    static func totalBytes(_ attachments: [AttachmentDraft]) -> Int {
        attachments.reduce(0) { $0 + $1.data.count }
    }

    static func canAppend(_ attachment: AttachmentDraft,
                          to attachments: [AttachmentDraft]) -> Bool {
        attachments.count < maxCount && totalBytes(attachments) + attachment.data.count <= maxTotalBytes
    }

    static func validateTotal(_ attachments: [AttachmentDraft]) throws {
        guard attachments.count <= maxCount,
              attachments.allSatisfy({ $0.data.count <= maxBytes }),
              totalBytes(attachments) <= maxTotalBytes else {
            throw Error.totalTooLarge
        }
    }

    static func image(data: Data, name: String) -> AttachmentDraft? {
        guard let source = UIImage(data: data) else { return nil }
        let longest = max(source.size.width, source.size.height)
        let scale = min(1, 1800 / max(1, longest))
        let size = CGSize(width: source.size.width * scale, height: source.size.height * scale)
        let rendered = UIGraphicsImageRenderer(size: size).image { _ in
            source.draw(in: CGRect(origin: .zero, size: size))
        }
        guard let compressed = rendered.jpegData(compressionQuality: 0.78),
              compressed.count <= maxBytes else { return nil }
        return AttachmentDraft(name: name, mimeType: "image/jpeg", data: compressed)
    }
}

struct CameraAttachmentPicker: UIViewControllerRepresentable {
    let onImage: (UIImage) -> Void
    let onCancel: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator(parent: self) }

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = UIImagePickerController.isSourceTypeAvailable(.camera)
            ? .camera : .photoLibrary
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

    final class Coordinator: NSObject, UINavigationControllerDelegate, UIImagePickerControllerDelegate {
        let parent: CameraAttachmentPicker
        init(parent: CameraAttachmentPicker) { self.parent = parent }
        func imagePickerController(_ picker: UIImagePickerController,
                                   didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            if let image = info[.originalImage] as? UIImage { parent.onImage(image) }
            else { parent.onCancel() }
        }
        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) { parent.onCancel() }
    }
}

/// PHPicker is available from iPadOS/iOS 14 and gives iOS 15 the same bounded,
/// privacy-preserving multi-image picker as newer systems.
struct PhotoLibraryAttachmentPicker: UIViewControllerRepresentable {
    let maxSelectionCount: Int
    let onImages: ([UIImage]) -> Void
    let onCancel: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator(parent: self) }

    func makeUIViewController(context: Context) -> PHPickerViewController {
        var configuration = PHPickerConfiguration()
        configuration.selectionLimit = maxSelectionCount
        configuration.filter = .images
        let picker = PHPickerViewController(configuration: configuration)
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: PHPickerViewController, context: Context) {}

    final class Coordinator: NSObject, PHPickerViewControllerDelegate {
        let parent: PhotoLibraryAttachmentPicker
        init(parent: PhotoLibraryAttachmentPicker) { self.parent = parent }

        func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
            guard !results.isEmpty else {
                parent.onCancel()
                return
            }
            loadItemProviders(results.map(\.itemProvider))
        }

        func loadItemProviders(_ providers: [NSItemProvider]) {
            let group = DispatchGroup()
            let lock = NSLock()
            var indexed: [(Int, UIImage)] = []
            for (index, provider) in providers.enumerated() {
                guard provider.canLoadObject(ofClass: UIImage.self) else { continue }
                group.enter()
                provider.loadObject(ofClass: UIImage.self) { object, _ in
                    if let image = object as? UIImage {
                        lock.lock()
                        indexed.append((index, image))
                        lock.unlock()
                    }
                    group.leave()
                }
            }
            group.notify(queue: .main) {
                self.parent.onImages(indexed.sorted { $0.0 < $1.0 }.map(\.1))
            }
        }
    }
}

// MARK: - formatting

enum Format {
    /// 1 769 → "1.8k", 15 574 679 → "15.6M"
    static func tokens(_ n: Int) -> String {
        switch n {
        case 0: return "—"
        case ..<1_000: return "\(n)"
        case ..<1_000_000: return String(format: "%.1fk", Double(n) / 1_000)
        default: return String(format: "%.1fM", Double(n) / 1_000_000)
        }
    }

    static func duration(_ seconds: TimeInterval) -> String {
        let s = Int(seconds)
        if s < 60 { return AppLocale.code == "ru" ? "\(s)с" : "\(s)s" }
        let m = s / 60
        if m < 60 { return AppLocale.code == "ru" ? "\(m)м" : "\(m)m" }
        let h = m / 60
        let rem = m % 60
        if h < 24 {
            if AppLocale.code == "ru" { return rem == 0 ? "\(h)ч" : "\(h)ч \(rem)м" }
            return rem == 0 ? "\(h)h" : "\(h)h \(rem)m"
        }
        return AppLocale.code == "ru" ? "\(h / 24)д \(h % 24)ч" : "\(h / 24)d \(h % 24)h"
    }
}

// MARK: - in-chat approvals (sheet covers root pendingSection)

/// Compact Allow / Yes-No strip above the chat composer.
/// Must never embed full `ApprovalCard` / `FilledButton` (both expand to ~½ screen).
/// When `sessionId` is set, prefer cards for that chat so yellow Allow is visible inside it.
