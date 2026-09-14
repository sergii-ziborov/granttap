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
                    Text(L("Secure approvals for coding agents on iPhone and iPad, with Apple Watch through iPhone."))
                        .multilineTextAlignment(.center)
                        .foregroundStyle(Theme.muted)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
            }

            Section(L("Product")) {
                CompatLabeledContent("Version", value: AppVersion.display)
                Text(L("GrantTap is an independent companion for supported coding agents. It does not provide an AI model or proxy model traffic."))
            }

            Section(L("Privacy by design")) {
                Label(L("End-to-end encrypted payloads"), systemImage: "lock.shield")
                Label(L("No account, advertising, tracking, or analytics"), systemImage: "hand.raised")
                Text(L("Visible activity is streamed only for an open session. Hidden reasoning is never forwarded."))
            }

            Section("Apple Watch") {
                Text(L("The watch displays synchronized state and sends decisions through the paired iPhone. A live network decision requires the companion connection."))
            }

            Section(L("Legal")) {
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
        .navigationTitle(L("About GrantTap"))
    }
}
