import SwiftUI
import UIKit

/// The pieces both composers are built from, so the home screen and a chat
/// ask for the next turn in the same shape.
///
/// A composer used to be a row of round buttons beside a capsule, with what
/// you had attached listed above it as text. Everything that belongs to the
/// message now sits inside one block: the pictures you attached, the words,
/// and under them the controls that decide how the turn runs.
struct AttachmentThumbnails: View {
    @Binding var attachments: [AttachmentDraft]

    var body: some View {
        if !attachments.isEmpty {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(attachments) { attachment in
                        ZStack(alignment: .topTrailing) {
                            thumbnail(attachment)
                            Button {
                                attachments.removeAll { $0.id == attachment.id }
                            } label: {
                                Image(systemName: "xmark")
                                    .font(.system(size: 9, weight: .heavy))
                                    .foregroundStyle(Theme.ink)
                                    .frame(width: 18, height: 18)
                                    .background(Theme.surface.opacity(0.94), in: Circle())
                                    .overlay(Circle().stroke(Theme.line, lineWidth: 1))
                            }
                            .buttonStyle(.plain)
                            .padding(3)
                            .accessibilityLabel(String(format: L("Remove %@"), attachment.name))
                        }
                    }
                }
                .padding(.vertical, 1)
            }
            .frame(height: 68)
        }
    }

    /// A picture shows the picture; anything else shows what it is called.
    @ViewBuilder private func thumbnail(_ attachment: AttachmentDraft) -> some View {
        let shape = RoundedRectangle(cornerRadius: 12, style: .continuous)
        if attachment.isImage, let image = UIImage(data: attachment.data) {
            Image(uiImage: image)
                .resizable()
                .scaledToFill()
                .frame(width: 62, height: 62)
                .clipShape(shape)
                .overlay(shape.stroke(Theme.line, lineWidth: 1))
                .accessibilityLabel(attachment.name)
        } else {
            VStack(spacing: 4) {
                Image(systemName: AttachmentGlyph.forName(attachment.name))
                    .font(.system(size: 16, weight: .semibold))
                Text(attachment.name)
                    .font(.system(size: 9, weight: .semibold))
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            .foregroundStyle(Theme.muted)
            .padding(.horizontal, 5)
            .frame(width: 62, height: 62)
            .background(Theme.raised, in: shape)
            .overlay(shape.stroke(Theme.line, lineWidth: 1))
        }
    }
}

/// The line the message is written on.
///
/// It grows with the text where the system can grow it, and stays one line
/// where it cannot: the phones this app still supports include one that
/// predates a text field with an axis.
struct ComposerField: View {
    let placeholder: String
    @Binding var text: String
    var focus: FocusState<Bool>.Binding
    let onSubmit: () -> Void

    var body: some View {
        Group {
            if #available(iOS 16.0, *) {
                TextField(placeholder, text: $text, axis: .vertical).lineLimit(1...6)
            } else {
                TextField(placeholder, text: $text)
            }
        }
        .font(.system(size: 16))
        .foregroundStyle(Theme.ink)
        .focused(focus)
        .submitLabel(.send)
        .onSubmit(onSubmit)
        .padding(.horizontal, 4)
        .padding(.top, 2)
    }
}

/// The pill that says which model the next turn will use, and changes it.
struct ComposerModelPill: View {
    let agent: String
    @Binding var model: TurnModel?
    /// What the chat is answering with when nothing was picked here — the
    /// model the computer reported, not the name of the agent that runs it.
    var current: String? = nil

    private var title: String {
        if let model { return model.label }
        if let current, !current.isEmpty {
            return TurnModel(rawValue: current)?.label ?? current
        }
        return AgentIdentity.displayName(agent)
    }

    var body: some View {
        let options = TurnModel.supported(by: agent)
        Menu {
            Button {
                model = nil
            } label: {
                Label(L("Whatever the chat uses"), systemImage: model == nil ? "checkmark" : "circle")
            }
            ForEach(options) { option in
                Button {
                    model = option
                } label: {
                    Label(option.label, systemImage: model == option ? "checkmark" : "circle")
                }
            }
        } label: {
            Text(title)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(model == nil ? Theme.muted : Theme.ink)
                .lineLimit(1)
                .padding(.horizontal, 13)
                .frame(height: 34)
                .background(Theme.raised, in: Capsule())
                .overlay(Capsule().stroke(Theme.line, lineWidth: 1))
        }
        .disabled(options.isEmpty)
        .accessibilityIdentifier("composer.model")
    }
}

/// Send, or put the keyboard away: one control, always in the same corner.
struct ComposerSendButton: View {
    let action: ComposerAction
    let tint: Color
    let glyphInk: Color
    var blocked: Bool = false
    let send: () -> Void
    let dismissKeyboard: () -> Void

    var body: some View {
        Button {
            if action == .send { send() } else { dismissKeyboard() }
        } label: {
            Image(systemName: action.systemImage)
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(action == .send ? glyphInk : Theme.muted)
                .frame(width: 34, height: 34)
                .background(action == .send ? AnyShapeStyle(tint) : AnyShapeStyle(Theme.line), in: Circle())
        }
        .disabled(action == .send && blocked)
        .accessibilityLabel(action == .send ? L("Send") : L("Close keyboard"))
    }
}

/// The block the whole message sits in.
struct ComposerBlock<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            content
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(Theme.raised, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous).stroke(Theme.line, lineWidth: 1)
        )
    }
}
