#if targetEnvironment(macCatalyst)
import SwiftUI

extension AttachmentMenuButton {
    var macAttachmentButton: some View {
        Button { showMacAttachmentPopover = true } label: {
            Image(systemName: "plus")
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(Theme.ink)
                .frame(width: 34, height: 34)
                .background(Theme.surface, in: Circle())
                .overlay(Circle().stroke(Theme.line, lineWidth: 1))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(L("Add to this message"))
        .popover(isPresented: $showMacAttachmentPopover,
                 attachmentAnchor: .rect(.bounds), arrowEdge: .bottom) {
            VStack(alignment: .leading, spacing: 4) {
                Text(String(format: L("Attachments · maximum %d"), AttachmentDraft.maxCount))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Theme.muted)
                    .padding(.horizontal, 10)
                macAttachmentChoice(photoLibraryLabel, "photo.on.rectangle") {
                    showMacAttachmentPopover = false
                    showPhotoLibrary = true
                }
                .disabled(atAttachmentLimit)
                macAttachmentChoice(L("Camera"), "camera") {
                    showMacAttachmentPopover = false
                    showCamera = true
                }
                .disabled(atAttachmentLimit || !cameraAvailable)
                macAttachmentChoice(L("Choose Files"), "folder") {
                    showMacAttachmentPopover = false
                    showFileImporter = true
                }
                .disabled(atAttachmentLimit)
                if !allowedMcpServers.isEmpty, let selectedMcp {
                    Divider()
                    Menu {
                        Button(L("Automatic")) { chooseMcp(nil) }
                        ForEach(allowedMcpServers) { server in
                            Button(server.name) { chooseMcp(server.name) }
                        }
                    } label: {
                        Label(selectedMcp.wrappedValue ?? L("Use an allowed MCP"),
                              systemImage: "shippingbox")
                    }
                }
                if !skills.isEmpty, let selectedSkill {
                    Menu {
                        Button(L("No explicit skill")) { chooseSkill(nil) }
                        ForEach(skills) { skill in
                            Button(skill.name) { chooseSkill(skill.name) }
                        }
                    } label: {
                        Label(selectedSkill.wrappedValue ?? L("Use a Mesh skill"),
                              systemImage: "wand.and.stars")
                    }
                }
            }
            .padding(12)
            .frame(width: 280, alignment: .leading)
        }
    }

    private func macAttachmentChoice(
        _ title: String, _ icon: String, action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Label(title, systemImage: icon)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 7)
                .padding(.horizontal, 10)
        }
        .buttonStyle(.plain)
    }
}
#endif
