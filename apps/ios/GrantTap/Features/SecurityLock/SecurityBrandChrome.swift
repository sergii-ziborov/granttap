import SwiftUI

/// Shared brand chrome for cold start, lock, PIN, and privacy shield.
struct GrantTapBrandMark: View {
    static let assetName = "BrandMark"
    var size: CGFloat = 56

    var body: some View {
        VStack(spacing: 10) {
            Image(Self.assetName)
                .resizable()
                .scaledToFit()
                .frame(width: size, height: size)
                .clipShape(RoundedRectangle(cornerRadius: size * 0.24, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: size * 0.24, style: .continuous)
                        .stroke(Theme.line, lineWidth: 1)
                )
            Text("GrantTap")
                .font(.system(size: 22, weight: .bold))
                .tracking(-0.3)
                .foregroundStyle(Theme.ink)
        }
    }
}

/// Prominent lock-screen identity: the app icon sits in a calm halo instead of
/// competing with a generic lock glyph or the navigation bar.
struct GrantTapLockBrand: View {
    static let haloSize: CGFloat = 116

    var body: some View {
        VStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(Theme.surface.opacity(0.74))
                    .overlay(Circle().stroke(Color.white.opacity(0.55), lineWidth: 1))
                    .shadow(color: Theme.claude.opacity(0.14), radius: 24, y: 12)
                    .frame(width: Self.haloSize, height: Self.haloSize)
                Image(GrantTapBrandMark.assetName)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 78, height: 78)
                    .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 20, style: .continuous)
                            .stroke(Color.white.opacity(0.24), lineWidth: 1)
                    )
                    .shadow(color: Color.black.opacity(0.12), radius: 8, y: 4)
            }
            Text("GRANTTAP")
                .font(.system(size: 16, weight: .black, design: .rounded))
                .tracking(2.2)
                .foregroundStyle(Theme.claude)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("GrantTap")
    }
}

struct SecurityLockBackdrop: View {
    var body: some View {
        ZStack {
            Theme.bg
            LinearGradient(
                colors: [
                    Theme.claudeCanvas.opacity(0.9),
                    Theme.bg.opacity(0.96),
                    Theme.codexCanvas.opacity(0.5),
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            Circle()
                .fill(Theme.claude.opacity(0.1))
                .frame(width: 330, height: 330)
                .blur(radius: 76)
                .offset(x: 120, y: -260)
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
    }
}

/// Identical cold-start frame whether Face ID is on or off.
struct GrantTapLaunchChrome: View {
    var body: some View {
        ZStack {
            Theme.bg.ignoresSafeArea()
            VStack(spacing: 0) {
                Spacer()
                VStack(spacing: 20) {
                    GrantTapBrandMark()
                    ProgressView()
                        .controlSize(.regular)
                        .tint(Theme.claude)
                    Text(L("Starting GrantTap…"))
                        .font(.footnote)
                        .foregroundStyle(Theme.muted)
                }
                Spacer()
                Text(L("Secure approvals for your agents"))
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.muted.opacity(0.85))
                    .padding(.bottom, 8)
                Capsule()
                    .fill(Theme.line)
                    .frame(width: 96, height: 4)
                    .padding(.bottom, 16)
            }
            .padding(.horizontal, 28)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(L("Starting GrantTap…"))
    }
}
