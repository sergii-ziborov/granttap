import SwiftUI
import PhotosUI
import UniformTypeIdentifiers
import UIKit

struct AttachmentStrip: View {
    @Binding var attachments: [AttachmentDraft]

    var body: some View {
        if !attachments.isEmpty {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 7) {
                    Text(String(format: L("%d/%d · %.1f/11 MB"),
                                attachments.count, AttachmentDraft.maxCount,
                                Double(AttachmentDraft.totalBytes(attachments)) / 1_000_000))
                        .font(Theme.mono(10.5, .semibold))
                        .foregroundStyle(Theme.muted)
                    ForEach(attachments) { attachment in
                        HStack(spacing: 6) {
                            Image(systemName: attachment.isImage ? "photo" : "doc")
                            Text(attachment.name).lineLimit(1)
                            Button {
                                attachments.removeAll { $0.id == attachment.id }
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                            }
                            .buttonStyle(.plain)
                        }
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Theme.muted)
                        .padding(.horizontal, 9)
                        .padding(.vertical, 6)
                        .background(Theme.raised, in: Capsule())
                        .overlay(Capsule().stroke(Theme.line, lineWidth: 1))
                    }
                }
            }
        }
    }
}

struct MessageRoutingStrip: View {
    @Binding var selectedMcp: String?
    @Binding var selectedSkill: String?

    var body: some View {
        if selectedMcp != nil || selectedSkill != nil {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 7) {
                    if let selectedMcp {
                        chip(icon: "shippingbox", text: "MCP: \(selectedMcp)") {
                            self.selectedMcp = nil
                        }
                    }
                    if let selectedSkill {
                        chip(icon: "wand.and.stars", text: "$\(selectedSkill)") {
                            self.selectedSkill = nil
                        }
                    }
                }
            }
        }
    }

    private func chip(icon: String, text: String, remove: @escaping () -> Void) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
            Text(text).lineLimit(1)
            Button(action: remove) { Image(systemName: "xmark.circle.fill") }
                .buttonStyle(.plain)
        }
        .font(.system(size: 11, weight: .semibold))
        .foregroundStyle(Theme.muted)
        .padding(.horizontal, 9)
        .padding(.vertical, 6)
        .background(Theme.raised, in: Capsule())
        .overlay(Capsule().stroke(Theme.line, lineWidth: 1))
    }
}
