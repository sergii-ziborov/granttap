import SwiftUI

struct SecurityLockView: View {
    @ObservedObject var security: SecurityGate
    var pendingCount: Int = 0

    var body: some View {
        ZStack {
            SecurityLockBackdrop()
            switch security.lockScreen {
            case .unlock, .pinEntry:
                unlockPane
            case .pinSetup(let confirming):
                PinPadView(
                    title: confirming ? L("Confirm PIN") : L("Create a PIN"),
                    subtitle: confirming
                        ? L("Enter the same 6 digits again")
                        : L("Use this PIN when Face ID is unavailable"),
                    cancelLabel: L("Cancel"),
                    onCancel: { security.cancelPinSetup() },
                    onComplete: { security.completePinSetupDigit($0) }
                )
            }
        }
    }

    private var unlockPane: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(spacing: 0) {
                welcomeHeader

                if pendingCount > 0 {
                    lockedPendingCard.padding(.top, 16)
                }

                Spacer(minLength: 22)
                unlockKeypad

                if let error = security.errorText {
                    Text(error)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Theme.riskHigh)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, 14)
                }

                Spacer(minLength: 20)
            }
            .padding(.horizontal, 18)
            .padding(.top, 22)
            .padding(.bottom, 16)
        }
    }

    private var unlockKeypad: some View {
        InlinePinPad(
            biometryName: offersBiometry ? security.biometryName : nil,
            authenticating: security.authenticating,
            onBiometry: biometryAction,
            onComplete: { security.unlockWithPin($0) }
        )
    }

    private var biometryAction: (() -> Void)? {
        guard offersBiometry else { return nil }
        return { security.unlockWithBiometry() }
    }

    private var welcomeHeader: some View {
        VStack(spacing: 10) {
            GrantTapLockBrand()
            Text(L("Welcome back"))
                .font(.system(size: 34, weight: .bold, design: .rounded))
                .tracking(-0.7)
                .foregroundStyle(Theme.ink)
                .padding(.top, 4)
            Text(String(
                format: L("Enter your 6-digit PIN or use %@"), security.biometryName
            ))
                .font(.system(size: 15))
                .multilineTextAlignment(.center)
                .foregroundStyle(Theme.muted)
                .frame(maxWidth: 320)
        }
    }

    private var offersBiometry: Bool {
        if case .unlock = security.lockScreen { return true }
        return false
    }

    private var lockedPendingCard: some View {
        HStack(spacing: 10) {
            Image(systemName: "bell.badge.fill")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Theme.riskMed)
            VStack(alignment: .leading, spacing: 2) {
                Text(pendingCount == 1
                     ? L("1 approval waiting")
                     : String(format: L("%d approvals waiting"), pendingCount))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Theme.ink)
                    .lineLimit(1)
                Text(L("Unlock to review"))
                    .font(.caption2)
                    .foregroundStyle(Theme.muted)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .frame(maxWidth: 430, alignment: .leading)
        .fixedSize(horizontal: false, vertical: true)
        .background(Theme.surface.opacity(0.8), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Theme.line, lineWidth: 1)
        )
    }
}
