import SwiftUI

struct PinPadView: View {
    let title: String
    let subtitle: String
    var cancelLabel: String = L("Back")
    let onCancel: () -> Void
    /// Return `true` to keep digits (advance handled by parent); `false` clears + shakes.
    let onComplete: (String) -> Bool

    @State private var digits = ""
    @State private var shake = 0

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Button(cancelLabel, action: onCancel)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Theme.ink)
                    .padding(.horizontal, 16)
                    .frame(height: 44)
                    .background(Theme.surface.opacity(0.82), in: Capsule())
                Spacer()
            }
            .padding(.horizontal, 20)
            .padding(.top, 12)

            VStack(spacing: 12) {
                Text(title)
                    .font(.system(size: 30, weight: .bold, design: .rounded))
                    .foregroundStyle(Theme.ink)
                Text(subtitle)
                    .font(.system(size: 15))
                    .foregroundStyle(Theme.muted)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 24)
                PinDots(filled: digits.count)
                    .modifier(ShakeEffect(animatableData: CGFloat(shake)))
                    .padding(.top, 8)
            }
            .padding(.top, 24)

            Spacer(minLength: 18)

            PinKeypad(onDigit: append, onDelete: backspace)
                .padding(.horizontal, 18)
                .padding(.bottom, 24)
        }
        .onChange(of: title) { _ in
            digits = ""
            shake = 0
        }
    }

    private func append(_ d: String) {
        guard digits.count < AppPinStore.length else { return }
        digits.append(d)
        if digits.count == AppPinStore.length {
            let pin = digits
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) {
                if onComplete(pin) { return }
                digits = ""
                withAnimation { shake += 1 }
            }
        }
    }

    private func backspace() {
        if !digits.isEmpty { digits.removeLast() }
    }
}

struct InlinePinPad: View {
    let onComplete: (String) -> Bool
    var biometryName: String?
    var authenticating: Bool
    var onBiometry: (() -> Void)?
    @State private var digits = ""
    @State private var shake = 0

    init(
        biometryName: String? = nil,
        authenticating: Bool = false,
        onBiometry: (() -> Void)? = nil,
        onComplete: @escaping (String) -> Bool
    ) {
        self.biometryName = biometryName
        self.authenticating = authenticating
        self.onBiometry = onBiometry
        self.onComplete = onComplete
    }

    var body: some View {
        VStack(spacing: 20) {
            PinDots(filled: digits.count)
                .modifier(ShakeEffect(animatableData: CGFloat(shake)))
            PinKeypad(
                onDigit: append,
                onDelete: backspace,
                biometryName: biometryName,
                biometryBusy: authenticating,
                onBiometry: onBiometry
            )
        }
    }

    private func append(_ digit: String) {
        guard digits.count < AppPinStore.length else { return }
        digits.append(digit)
        guard digits.count == AppPinStore.length else { return }
        let pin = digits
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) {
            if onComplete(pin) { return }
            digits = ""
            withAnimation { shake += 1 }
        }
    }

    private func backspace() {
        if !digits.isEmpty { digits.removeLast() }
    }
}
