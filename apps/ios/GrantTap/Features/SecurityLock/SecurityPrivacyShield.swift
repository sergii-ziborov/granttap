import SwiftUI

struct SecurityPrivacyShield: View {
    var body: some View {
        ZStack {
            Theme.bg.ignoresSafeArea()
            VStack(spacing: 12) {
                GrantTapBrandMark(size: 48)
                Text(L("Task details are hidden while GrantTap is not active."))
                    .font(.footnote)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(Theme.muted)
                    .padding(.horizontal, 28)
            }
        }
        .accessibilityHidden(true)
    }
}
