import SwiftUI
import WatchKit

struct Pill: View {
    let title: String
    var icon: String? = nil
    var height: CGFloat = 34
    var width: CGFloat? = nil          // nil → take all available width
    var fill: Color = Color.white.opacity(0.14)
    var textColor: Color = .white
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: title.isEmpty ? 0 : pt(4)) {
                if let icon {
                    Image(systemName: icon)
                        .font(.system(size: height * 0.36, weight: .bold))
                }
                if !title.isEmpty {
                    Text(L(title))
                        .font(.system(size: height * 0.4, weight: .semibold))
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                }
            }
            .foregroundStyle(textColor)
            .frame(maxWidth: width == nil ? .infinity : nil)
            .frame(width: width, height: height)
            .background(fill, in: Capsule())
        }
        .buttonStyle(.plain)
    }
}

/// Button-shaped watchOS text entry. The system presents the user's last input
/// method (keyboard, Scribble, or Dictation); the mic remains visible in every
/// chat and Activity view.
struct ReplyInput: View {
    let title: String
    let icon: String
    var height: CGFloat = 30
    var fill: Color = Color.white.opacity(0.14)
    var textColor: Color = .white
    var iconOnly = false
    var prompt = "Reply to this session"
    var normalizeTechnologyTerms = false
    let onSubmit: (String) -> Void

    var body: some View {
        TextFieldLink(
            prompt: Text(L(prompt)),
            label: {
                HStack(spacing: pt(4)) {
                    Image(systemName: icon)
                        .font(.system(size: height * 0.34, weight: .bold))
                    if !iconOnly {
                        Text(L(title))
                            .font(.system(size: height * 0.38, weight: .semibold))
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                    }
                }
                .foregroundStyle(textColor)
                .frame(maxWidth: iconOnly ? nil : .infinity)
                .frame(width: iconOnly ? height : nil)
                .frame(height: height)
                .background(fill, in: Capsule())
            },
            onSubmit: submit
        )
        .buttonStyle(.plain)
    }

    func submit(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let result = normalizeTechnologyTerms ? VoiceTextNormalizer.normalize(trimmed) : trimmed
        if !result.isEmpty { onSubmit(result) }
    }
}
