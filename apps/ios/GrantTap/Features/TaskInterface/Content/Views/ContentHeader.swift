import SwiftUI

extension ContentView {
    private var onboardingDescription: String {
        #if targetEnvironment(macCatalyst)
        return L("Control your coding agents from this Mac.")
        #else
        return L("Control your coding agents from iPhone and Apple Watch.")
        #endif
    }

    var notPairedCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Image("BrandMark")
                .resizable()
                .scaledToFit()
                .frame(width: 54, height: 54)
                .clipShape(RoundedRectangle(cornerRadius: 14))
            Text("GrantTap")
                .font(.system(size: 26, weight: .bold))
                .foregroundStyle(Theme.ink)
            Text(onboardingDescription)
                .font(.system(size: 14))
                .foregroundStyle(Theme.muted)
                .fixedSize(horizontal: false, vertical: true)

            Button(L("Connect a computer")) { showPairing = true }
                .buttonStyle(FilledButton(tint: Theme.claude))
            Button(L("Explore demo")) { model.startDemo() }
                .buttonStyle(OutlineButton(tint: Theme.ink))
        }
        .card()
    }

    // MARK: pending approvals
}
