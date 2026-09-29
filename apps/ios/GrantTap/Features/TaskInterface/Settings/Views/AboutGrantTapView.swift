import SwiftUI
import PhotosUI
import UniformTypeIdentifiers
import UIKit

struct PushStatusLabel: View {
    let state: PushRegistrationManager.State
    var body: some View {
        switch state {
        case .idle: Text(L("Waiting")).foregroundStyle(Theme.muted)
        case .registering: ProgressView().controlSize(.small)
        case .active: Label(L("Active"), systemImage: "checkmark.circle.fill").foregroundStyle(Theme.ok)
        case .unavailable(let reason), .failed(let reason):
            VStack(alignment: .trailing, spacing: 2) {
                Label(L("Unavailable"), systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(Theme.riskHigh)
                Text(reason)
                    .font(.caption2)
                    .foregroundStyle(Theme.muted)
                    .multilineTextAlignment(.trailing)
                    .lineLimit(3)
            }
        }
    }
}

enum GrantTapLinks {
    static let all: [(String, String)] = [
        ("Website", "https://granttap.com"),
        ("Apple apps source", "https://github.com/sergii-ziborov/granttap"),
        ("Mac license terms", "https://github.com/sergii-ziborov/granttap/blob/main/apps/macos/DESKTOP_EULA.md"),
        ("MCP source", "https://github.com/sergii-ziborov/granttap-mcp"),
        ("npm package", "https://www.npmjs.com/package/granttap-mcp"),
        ("Relay source", "https://github.com/sergii-ziborov/granttap-relay"),
        ("Privacy", "https://granttap.com/privacy"),
        ("Terms", "https://granttap.com/terms"),
        ("Support", "https://granttap.com/support"),
        ("Licenses", "https://granttap.com/licenses"),
    ]
}

struct AboutGrantTapView: View {
    var body: some View {
        List {
            Section {
                VStack(spacing: 10) {
                    Image("BrandMark")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 74, height: 74)
                        .clipShape(RoundedRectangle(cornerRadius: 17, style: .continuous))
                        .accessibilityHidden(true)
                    Text("GrantTap")
                        .font(.title2.bold())
                    Text(L("Mesh, Governance, and live control for coding agents across Mac, iPhone, iPad, and Apple Watch."))
                        .multilineTextAlignment(.center)
                        .foregroundStyle(Theme.muted)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
            }

            Section(L("Product")) {
                CompatLabeledContent("Version", value: AppVersion.display)
                Text(L("GrantTap coordinates local coding agents, chat policy, shared evidence, and human decisions. It does not provide an AI model or proxy model traffic."))
            }

            #if targetEnvironment(macCatalyst)
            Section(L("Mac license")) {
                Text(L("One-time Mac license. Personal is optional for hosted delivery; direct or own-relay operation requires no subscription."))
                NavigationLink(L("Purchase or restore Mac license")) { DesktopLicenseView() }
            }
            #endif

            Section(L("Privacy by design")) {
                Label(L("End-to-end encrypted payloads"), systemImage: "lock.shield")
                Label(L("No account, advertising, tracking, or analytics"), systemImage: "hand.raised")
                Text(L("Visible activity is streamed only for an open session. Hidden reasoning is never forwarded."))
            }

            Section("Apple Watch") {
                Text(L("The watch displays synchronized state and sends decisions through the paired iPhone. A live network decision requires the companion connection."))
            }

            Section(L("Legal")) {
                ProductInformationLinks()
            }

            Section(L("Website and source")) {
                ForEach(Array(GrantTapLinks.all.enumerated()), id: \.offset) { _, item in
                    if let url = URL(string: item.1) {
                        Link(L(item.0), destination: url)
                    }
                }
            }

            Section {
                Text(L("Apple, Apple Watch, iPhone, and App Store are trademarks of Apple Inc. Claude and Claude Code are trademarks of Anthropic. OpenAI and Codex are trademarks of OpenAI. GrantTap is not affiliated with or endorsed by those companies."))
                    .font(.footnote)
                    .foregroundStyle(Theme.muted)
                Text(L("© 2026 Serhii Ziborov. All rights reserved."))
                    .font(.footnote)
                    .foregroundStyle(Theme.muted)
            }
        }
        .pageNavigationTitle(L("About GrantTap"))
    }
}
