#if targetEnvironment(macCatalyst)
import SwiftUI
import UIKit

struct MacLocalMCPWelcomeView: View {
    let checked: Bool
    let refreshing: Bool
    let found: Bool
    let onRetry: () -> Void
    let onSettings: () -> Void

    @ObservedObject private var access = MacNativeAccess.shared
    private let installURL = URL(string: "https://granttap.com/#install")!

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                HStack(spacing: 12) {
                    Image("BrandMark")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 42, height: 42)
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                    Text("GrantTap")
                        .font(.system(size: 24, weight: .bold))
                }

                if !checked {
                    HStack(spacing: 12) {
                        ProgressView()
                        Text(L("Checking GrantTap MCP on this Mac…"))
                    }
                    .foregroundStyle(Theme.muted)
                } else {
                    Text(found
                         ? L("GrantTap MCP cannot read this Mac's Mesh yet.")
                         : L("GrantTap MCP is unavailable on this Mac."))
                        .font(.system(size: 19, weight: .semibold))
                    Text(found
                         ? L("Check the local MCP service and try again.")
                         : L("Install GrantTap MCP on this Mac, then check again. If it is already installed, make sure its local service is running."))
                        .foregroundStyle(Theme.muted)
                        .fixedSize(horizontal: false, vertical: true)

                    if found {
                        Button(L("Authorize local Mac access")) {
                            Task { await access.authorize(); onRetry() }
                        }.disabled(access.busy)
                        if let error = access.lastError { Text(error).foregroundStyle(Theme.riskHigh) }
                    }
                    if !found {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("npm install -g granttap-mcp")
                                .font(Theme.mono(13))
                                .textSelection(.enabled)
                            HStack(spacing: 12) {
                                Link(L("Install GrantTap MCP"), destination: installURL)
                                    .buttonStyle(FilledButton(tint: Theme.claude))
                                Button {
                                    UIPasteboard.general.string = "npm install -g granttap-mcp"
                                } label: {
                                    Label(L("Copy command"), systemImage: "doc.on.doc")
                                }
                                .buttonStyle(OutlineButton(tint: Theme.ink))
                            }
                        }
                        .padding(16)
                        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 18))
                    }

                    HStack(spacing: 12) {
                        Button(action: onRetry) {
                            Label(L("Check again"), systemImage: "arrow.clockwise")
                        }
                        .disabled(refreshing)
                        Button(L("Settings"), action: onSettings)
                    }
                }
            }
            .frame(maxWidth: 560, alignment: .leading)
            .padding(32)
            .frame(maxWidth: .infinity, minHeight: 480, alignment: .top)
        }
        .background(Theme.bg)
    }
}
#endif
