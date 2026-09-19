import SwiftUI
import PhotosUI
import UniformTypeIdentifiers
import UIKit

struct AttachmentMenuButton: View {
    @Binding var attachments: [AttachmentDraft]
    var mcpServers: [McpServerInfo] = []
    var skills: [SkillInfo] = []
    var selectedMcp: Binding<String?>? = nil
    var selectedSkill: Binding<String?>? = nil
    @State private var showPhotoLibrary = false
    @State private var showCamera = false
    @State private var showSketch = false
    @State private var showFileImporter = false
    @State private var errorText: String?

    init(
        attachments: Binding<[AttachmentDraft]>,
        mcpServers: [McpServerInfo] = [],
        skills: [SkillInfo] = [],
        selectedMcp: Binding<String?>? = nil,
        selectedSkill: Binding<String?>? = nil,
        showPhotoLibrary: Bool = false,
        showCamera: Bool = false,
        showSketch: Bool = false,
        showFileImporter: Bool = false,
        errorText: String? = nil
    ) {
        _attachments = attachments
        self.mcpServers = mcpServers
        self.skills = skills
        self.selectedMcp = selectedMcp
        self.selectedSkill = selectedSkill
        _showPhotoLibrary = State(initialValue: showPhotoLibrary)
        _showCamera = State(initialValue: showCamera)
        _showSketch = State(initialValue: showSketch)
        _showFileImporter = State(initialValue: showFileImporter)
        _errorText = State(initialValue: errorText)
    }

    var body: some View {
        Menu {
            Section(String(format: L("Attachments · maximum %d"), AttachmentDraft.maxCount)) {
                Button { showPhotoLibrary = true } label: {
                    Label(photoLibraryLabel, systemImage: "photo.on.rectangle")
                }
                .disabled(atAttachmentLimit)
                Button { showCamera = true } label: {
                    Label(L("Camera"), systemImage: "camera")
                }
                .disabled(atAttachmentLimit || !cameraAvailable)
                Button { showSketch = true } label: {
                    Label(L("Draw a sketch"), systemImage: "pencil.and.outline")
                }
                .disabled(atAttachmentLimit)
                Button { showFileImporter = true } label: {
                    Label(L("Choose Files"), systemImage: "folder")
                }
                .disabled(atAttachmentLimit)
            }

            if !allowedMcpServers.isEmpty, let selectedMcp {
                Menu {
                    Button { chooseMcp(nil) } label: {
                        Label(L("Automatic"), systemImage: selectedMcp.wrappedValue == nil
                              ? "checkmark" : "circle")
                    }
                    ForEach(allowedMcpServers) { server in
                        Button { chooseMcp(server.name) } label: {
                            Label(server.name,
                                  systemImage: selectedMcp.wrappedValue == server.name
                                  ? "checkmark" : "circle")
                        }
                    }
                } label: {
                    Label(L("Use an allowed MCP"), systemImage: "shippingbox")
                }
            }

            if !skills.isEmpty, let selectedSkill {
                Menu {
                    Button { chooseSkill(nil) } label: {
                        Label(L("No explicit skill"), systemImage: selectedSkill.wrappedValue == nil
                              ? "checkmark" : "circle")
                    }
                    ForEach(skills) { skill in
                        Button { chooseSkill(skill.name) } label: {
                            Label(skill.name,
                                  systemImage: selectedSkill.wrappedValue == skill.name
                                  ? "checkmark" : "circle")
                        }
                    }
                } label: {
                    Label(L("Use a project skill"), systemImage: "wand.and.stars")
                }
            }
        } label: {
            // One way in to everything a turn can carry, in the corner of the
            // block the message is written in.
            Image(systemName: "plus")
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(Theme.ink)
                .frame(width: 34, height: 34)
                .background(Theme.surface, in: Circle())
                .overlay(Circle().stroke(Theme.line, lineWidth: 1))
        }
        .accessibilityLabel(L("Add to this message"))
        .sheet(isPresented: $showPhotoLibrary) {
            PhotoLibraryAttachmentPicker(
                maxSelectionCount: max(1, AttachmentDraft.maxCount - attachments.count),
                onImages: completePhotoLibrary,
                onCancel: cancelPhotoLibrary
            )
            .ignoresSafeArea()
        }
        .fullScreenCover(isPresented: $showCamera) {
            CameraAttachmentPicker(
                onImage: completeCamera,
                onCancel: cancelCamera
            )
            .ignoresSafeArea()
        }
        .fullScreenCover(isPresented: $showSketch) {
            SketchAttachmentScreen(
                onComplete: completeSketch,
                onCancel: cancelSketch
            )
        }
        .fileImporter(isPresented: $showFileImporter,
                      allowedContentTypes: [.item], allowsMultipleSelection: true) { result in
            importFiles(result)
        }
        .alert(L("Could not attach file"), isPresented: errorPrompt) {
            Button(L("OK"), role: .cancel) {}
        } message: {
            Text(errorText ?? L("Unknown attachment error."))
        }
    }

    var allowedMcpServers: [McpServerInfo] {
        mcpServers.filter(\.allowed)
    }

    var atAttachmentLimit: Bool {
        attachments.count >= AttachmentDraft.maxCount ||
            AttachmentDraft.totalBytes(attachments) >= AttachmentDraft.maxTotalBytes
    }

    var cameraAvailable: Bool {
        UIImagePickerController.isSourceTypeAvailable(.camera)
    }

    var photoLibraryLabel: String {
        let remaining = max(0, AttachmentDraft.maxCount - attachments.count)
        return String(format: L("Photo Library · select up to %d"), remaining)
    }

    var errorPrompt: Binding<Bool> {
        Binding(
            get: { errorText != nil },
            set: { if !$0 { errorText = nil } }
        )
    }

    func chooseMcp(_ name: String?) { selectedMcp?.wrappedValue = name }

    func chooseSkill(_ name: String?) { selectedSkill?.wrappedValue = name }

    func completePhotoLibrary(_ images: [UIImage]) {
        showPhotoLibrary = false
        addLibraryImages(images)
    }

    func cancelPhotoLibrary() { showPhotoLibrary = false }

    func completeCamera(_ image: UIImage) {
        showCamera = false
        addPreparedImage(image, name: "Camera-\(attachments.count + 1).jpg")
    }

    func cancelCamera() { showCamera = false }

    func completeSketch(_ image: UIImage) {
        showSketch = false
        addPreparedImage(image, name: "Sketch-\(attachments.count + 1).jpg")
    }

    func cancelSketch() { showSketch = false }

    func addLibraryImages(_ images: [UIImage]) {
        var projectedBytes = AttachmentDraft.totalBytes(attachments)
        for image in images.prefix(max(0, AttachmentDraft.maxCount - attachments.count)) {
            guard let data = image.jpegData(compressionQuality: 0.9),
                  let draft = AttachmentDraft.image(
                    data: data,
                    name: "Photo-\(attachments.count + 1).jpg"
                  ) else { continue }
            guard projectedBytes + draft.data.count <= AttachmentDraft.maxTotalBytes else {
                errorText = AttachmentDraft.Error.totalTooLarge.localizedDescription
                return
            }
            projectedBytes += draft.data.count
            attachments.append(draft)
        }
    }

    func addCameraImage(_ image: UIImage) {
        addPreparedImage(image, name: "Camera-\(attachments.count + 1).jpg")
    }

    func addPreparedImage(_ image: UIImage, name: String) {
        guard attachments.count < AttachmentDraft.maxCount else {
            errorText = String(
                format: L("The image could not be prepared or the %d-file limit was reached."),
                AttachmentDraft.maxCount
            )
            return
        }
        guard let data = image.jpegData(compressionQuality: 0.78),
              let draft = AttachmentDraft.image(data: data, name: name) else {
            errorText = String(
                format: L("The image could not be prepared or the %d-file limit was reached."),
                AttachmentDraft.maxCount
            )
            return
        }
        guard AttachmentDraft.canAppend(draft, to: attachments) else {
            errorText = AttachmentDraft.Error.totalTooLarge.localizedDescription
            return
        }
        attachments.append(draft)
    }

    func importFiles(_ result: Result<[URL], Error>) {
        do {
            for url in try result.get().prefix(max(0, AttachmentDraft.maxCount - attachments.count)) {
                let scoped = url.startAccessingSecurityScopedResource()
                defer { if scoped { url.stopAccessingSecurityScopedResource() } }
                let data = try Data(contentsOf: url, options: .mappedIfSafe)
                guard data.count <= AttachmentDraft.maxBytes else {
                    throw AttachmentDraft.Error.tooLarge(url.lastPathComponent)
                }
                let mime = UTType(filenameExtension: url.pathExtension)?.preferredMIMEType
                    ?? "application/octet-stream"
                let draft = AttachmentDraft(name: url.lastPathComponent,
                                            mimeType: mime, data: data)
                guard AttachmentDraft.canAppend(draft, to: attachments) else {
                    throw AttachmentDraft.Error.totalTooLarge
                }
                attachments.append(draft)
            }
        } catch {
            errorText = error.localizedDescription
        }
    }
}
