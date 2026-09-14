import SwiftUI

struct PinDots: View {
    let filled: Int
    var total: Int = AppPinStore.length

    var body: some View {
        HStack(spacing: 14) {
            ForEach(0..<total, id: \.self) { i in
                Circle()
                    .strokeBorder(i < filled ? Theme.claude : Theme.ink.opacity(0.3), lineWidth: 1.8)
                    .background(Circle().fill(i < filled ? Theme.claude : Color.clear))
                    .frame(width: 14, height: 14)
            }
        }
        .animation(.easeOut(duration: 0.16), value: filled)
    }
}

struct PinKeypad: View {
    static let keyHeight: CGFloat = 68
    static let keySpacing: CGFloat = 10

    let onDigit: (String) -> Void
    let onDelete: () -> Void
    var biometryName: String? = nil
    var biometryBusy = false
    var onBiometry: (() -> Void)? = nil
    private let keys = ["1", "2", "3", "4", "5", "6", "7", "8", "9", "", "0", "⌫"]

    var body: some View {
        LazyVGrid(
            columns: Array(
                repeating: GridItem(.flexible(), spacing: Self.keySpacing), count: 3
            ),
            spacing: Self.keySpacing
        ) {
            ForEach(Array(keys.enumerated()), id: \.offset) { _, key in
                if key.isEmpty {
                    biometryKey
                } else if key == "⌫" {
                    Button(action: onDelete) {
                        Image(systemName: "delete.left")
                            .font(.system(size: 23, weight: .semibold))
                    }
                    .buttonStyle(PinKeyStyle(foreground: Theme.muted))
                    .accessibilityLabel(L("Delete digit"))
                } else {
                    Button(key) { onDigit(key) }
                        .buttonStyle(PinKeyStyle())
                }
            }
        }
        .frame(maxWidth: 430)
        .frame(maxWidth: .infinity)
    }

    @ViewBuilder private var biometryKey: some View {
        if let name = biometryName, let onBiometry {
            Button(action: onBiometry) {
                VStack(spacing: 3) {
                    if biometryBusy {
                        ProgressView().tint(Theme.claude)
                    } else {
                        Image(systemName: biometrySymbol(name))
                            .font(.system(size: 25, weight: .medium))
                    }
                    Text(name)
                        .font(.system(size: 11, weight: .semibold))
                        .lineLimit(1)
                }
            }
            .buttonStyle(PinKeyStyle(
                foreground: Theme.claude,
                fill: Theme.claudeCanvas.opacity(0.95)
            ))
            .disabled(biometryBusy)
            .accessibilityLabel(String(format: L("Unlock with %@"), name))
        } else {
            Color.clear
                .frame(height: Self.keyHeight)
                .accessibilityHidden(true)
        }
    }

    private func biometrySymbol(_ name: String) -> String {
        name.lowercased().contains("touch") ? "touchid" : "faceid"
    }
}

struct PinKeyStyle: ButtonStyle {
    var foreground: Color = Theme.ink
    var fill: Color = Theme.surface.opacity(0.88)

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 24, weight: .semibold, design: .rounded))
            .foregroundStyle(foreground)
            .frame(maxWidth: .infinity)
            .frame(height: PinKeypad.keyHeight)
            .background(fill, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(Theme.line.opacity(0.8), lineWidth: 1)
            )
            .shadow(color: Color.black.opacity(0.035), radius: 2, y: 1)
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .opacity(configuration.isPressed ? 0.82 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

struct ShakeEffect: GeometryEffect {
    var animatableData: CGFloat
    func effectValue(size: CGSize) -> ProjectionTransform {
        let x = 8 * sin(animatableData * .pi * 3)
        return ProjectionTransform(CGAffineTransform(translationX: x, y: 0))
    }
}
