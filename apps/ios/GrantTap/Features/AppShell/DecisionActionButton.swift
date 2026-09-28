import SwiftUI

/// Keeps phone actions full width while using compact controls in Mac cards.
struct DecisionActionButton: View {
    let title: String
    let tint: Color
    var filled = true
    var textColor: Color = .white
    let action: () -> Void

    var body: some View {
        #if targetEnvironment(macCatalyst)
        Button(action: action) {
            Text(title)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(filled ? textColor : tint)
                .padding(.horizontal, 16)
                .frame(minWidth: 88, minHeight: 30)
                .background(
                    filled ? tint : Color.clear,
                    in: RoundedRectangle(cornerRadius: 8, style: .continuous)
                )
                .overlay {
                    if !filled {
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .stroke(tint.opacity(0.55), lineWidth: 1)
                    }
                }
        }
        .buttonStyle(.plain)
        #else
        if filled {
            Button(title, action: action)
                .buttonStyle(FilledButton(tint: tint, textColor: textColor))
        } else {
            Button(title, action: action)
                .buttonStyle(OutlineButton(tint: tint))
        }
        #endif
    }
}
