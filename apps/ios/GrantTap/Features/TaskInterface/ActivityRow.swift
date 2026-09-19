import SwiftUI
import PhotosUI
import UniformTypeIdentifiers
import UIKit

/// A tapped attachment, held just long enough to present its full image.
struct ImagePreview: Identifiable {
    let id = UUID()
    let image: UIImage
}

/// The one mark that says "this folds": a chevron on the label itself, in
/// the row's colour, on a small disc — not a grey arrow off at the far edge
/// that read as a separate control.
struct FoldChevron: View {
    let open: Bool
    let accent: Color

    var body: some View {
        Image(systemName: open ? "chevron.up" : "chevron.down")
            .font(.system(size: 8, weight: .heavy))
            .foregroundStyle(accent)
            .frame(width: 16, height: 16)
            .background(Circle().fill(accent.opacity(0.14)))
            .accessibilityHidden(true)
    }
}

struct ActivityRow: View {
    @EnvironmentObject private var model: AppModel
    @State private var previewImage: ImagePreview?
    @State private var expanded: Bool
    let entry: ActivityEntry
    let accent: Color
    let compact: Bool
    var server: McpServerInfo? = nil
    /// Off inside an opened run: the run is the fold, its calls are plain.
    var folds: Bool = true

    init(
        entry: ActivityEntry, accent: Color, compact: Bool,
        server: McpServerInfo? = nil, initiallyExpanded: Bool = false, folds: Bool = true
    ) {
        self.entry = entry
        self.accent = accent
        self.compact = compact
        self.server = server
        self.folds = folds
        _expanded = State(initialValue: initiallyExpanded)
    }

    /// A tool call folds to its label, cost and one line of command, the way
    /// a run of them does; a wall of one command was as hard to scroll past
    /// as a wall of six.
    private var foldable: Bool { entry.kind == "tool" && !compact && folds }
    private var folded: Bool { foldable && !expanded }

    /// What a person sent, said the way a person's message is said: in its
    /// own block, without the eyebrow and icon an agent's row carries.
    private var isFromPerson: Bool { entry.kind == "user" && !compact }

    var body: some View {
        if isFromPerson {
            personRow
        } else {
            agentRow
        }
    }

    private var personRow: some View {
        HStack(alignment: .top, spacing: 0) {
            Spacer(minLength: 32)
            VStack(alignment: .leading, spacing: 7) {
                if !entry.text.isEmpty {
                    RichMessageText(text: entry.text, compact: false)
                }
                attachments
                if let tick = model.deliveryTick(forEntryId: entry.id) {
                    DeliveryTicksView(
                        tick: tick,
                        onRetry: model.deliveryRetryId(forEntryId: entry.id).map { id in
                            { model.retryDelivery(id) }
                        }
                    )
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 11)
            .background(Theme.raised, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(Theme.line, lineWidth: 1)
            )
        }
        .accessibilityIdentifier("chat.row.\(entry.id)")
        .fullScreenCover(item: $previewImage) { preview in
            ImagePreviewScreen(image: preview.image) { previewImage = nil }
        }
    }

    private var agentRow: some View {
        HStack(alignment: .top, spacing: 8) {
            if let server = entry.mcpServer {
                MCPBadge(name: server, size: 22, server: self.server)
            } else {
                Image(systemName: icon)
                    .foregroundStyle(entry.kind == "tool" ? accent : Theme.muted)
                    .frame(width: 18)
            }
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(rowLabel)
                        .font(.system(size: 9, weight: .heavy))
                        .foregroundStyle(rowLabelColor)
                    if let tokens = entry.estimatedContextTokens, tokens > 0 {
                        Text("· \(Format.tokens(tokens)) tok")
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(Theme.muted)
                    }
                    if let stats = entry.diffStats { DiffStatsBadge(added: stats.added, removed: stats.removed) }
                    if foldable { FoldChevron(open: expanded, accent: accent) }
                }
                .contentShape(Rectangle())
                .onTapGesture { if foldable { withAnimation(.easeInOut(duration: 0.15)) { expanded.toggle() } } }
                .accessibilityAddTraits(foldable ? .isButton : [])
                .accessibilityIdentifier(foldable ? "chat.call.\(entry.id)" : "chat.row.\(entry.id)")
                // One call shows what it cost the same way a folded run does;
                // the number did not stop mattering because the call was alone.
                if let metrics = entry.cliMetricsLine {
                    Text(metrics)
                        .font(.system(size: 10))
                        .foregroundStyle(Theme.muted)
                }
                if entry.kind == "tool" {
                    Text(folded ? ChatTranscriptText.display(entry.oneLinePreview) : ChatTranscriptText.display(entry.text))
                        .font(Theme.mono(compact ? 10.5 : 11.5))
                        .foregroundStyle(folded ? Theme.muted : Theme.ink)
                        .lineLimit(folded ? 1 : (compact ? 2 : nil))
                        .truncationMode(.tail)
                        .contentShape(Rectangle())
                        .onTapGesture { if foldable { withAnimation(.easeInOut(duration: 0.15)) { expanded.toggle() } } }
                    // Opened, a file tool shows the change the way git does:
                    // what went in green, what came out red.
                    if !folded, !compact, let preview = entry.diffPreview, !preview.isEmpty {
                        DiffPreviewView(text: preview)
                    }
                } else if !entry.text.isEmpty {
                    RichMessageText(text: entry.text, compact: compact)
                }
                // The delivery mark rides on the message itself, the way a
                // messenger shows it — not as a second copy below the chat.
                if let tick = model.deliveryTick(forEntryId: entry.id) {
                    DeliveryTicksView(
                        tick: tick,
                        onRetry: model.deliveryRetryId(forEntryId: entry.id).map { id in
                            { model.retryDelivery(id) }
                        }
                    )
                }
                attachments
            }
            Spacer(minLength: 0)
        }
        .fullScreenCover(item: $previewImage) { preview in
            ImagePreviewScreen(image: preview.image) { previewImage = nil }
        }
    }

    /// A photo sent without a caption is still a message. A picture this phone
    /// still holds is shown as the picture; one known only by name in a
    /// transcript says its name and opens nothing rather than a broken frame.
    @ViewBuilder private var attachments: some View {
        if let names = entry.attachments, !names.isEmpty {
            ForEach(names, id: \.self) { name in
                let image = model.sentAttachmentImage(forEntryId: entry.id, name: name)
                Button {
                    if let image { previewImage = ImagePreview(image: image) }
                } label: {
                    if let image {
                        Image(uiImage: image)
                            .resizable()
                            .scaledToFill()
                            .frame(maxWidth: 220, maxHeight: 220)
                            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                            .overlay(
                                RoundedRectangle(cornerRadius: 14, style: .continuous)
                                    .stroke(Theme.line, lineWidth: 1)
                            )
                            .accessibilityLabel(name)
                    } else {
                        Label(name, systemImage: AttachmentGlyph.forName(name))
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(Theme.muted)
                            .lineLimit(1)
                    }
                }
                .buttonStyle(.plain)
                .disabled(image == nil)
                #if DEBUG
                .onAppear {
                    if ProcessInfo.processInfo.environment[
                        "GRANTTAP_IMAGE_PREVIEW_SCREENSHOT"
                    ] != nil, let image {
                        previewImage = ImagePreview(image: image)
                    }
                }
                #endif
            }
        }
    }

    private var icon: String {
        if entry.mcpServer != nil { return "shippingbox" }
        if entry.skill != nil { return "wand.and.stars" }
        switch entry.kind {
        case "user": return "person.crop.circle"
        case "tool": return ToolRowLabel.icon(for: entry)
        case "final": return "checkmark.circle"
        case "status": return "clock"
        default: return "text.bubble"
        }
    }

    private var rowLabel: String {
        if let server = entry.mcpServer {
            return "MCP · \(self.server?.displayTitle ?? MCPIdentity(name: server).displayName)"
        }
        if let skill = entry.skill { return "SKILL · \(skill)" }
        if entry.kind == "tool" { return ToolRowLabel.text(for: entry) }
        switch entry.kind {
        case "user": return L("YOU")
        case "final": return L("FINAL")
        case "status": return L("STATUS")
        default: return L("AGENT")
        }
    }

    private var rowLabelColor: Color {
        if entry.mcpServer != nil { return Theme.codex }
        if entry.skill != nil { return Theme.claude }
        if entry.kind == "tool" { return accent }
        return Theme.muted
    }
}
