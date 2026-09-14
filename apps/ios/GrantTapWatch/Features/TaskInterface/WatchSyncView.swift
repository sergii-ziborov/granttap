import SwiftUI
import WatchKit

struct WatchSyncView: View {
    @StateObject private var bridge = WatchBridge.shared

    private var statusText: String {
        if !bridge.linkActive { return L("Connecting to iPhone…") }
        if bridge.phoneReachable { return L("Requesting current tasks…") }
        return L("Open GrantTap on the paired iPhone to sync.")
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: pt(9)) {
                Image(systemName: bridge.phoneReachable ? "iphone.radiowaves.left.and.right" : "iphone.slash")
                    .font(.system(size: pt(28), weight: .semibold))
                    .foregroundStyle(bridge.phoneReachable ? .green : .orange)

                Text(L("Waiting for iPhone"))
                    .font(.system(size: pt(15), weight: .bold))
                    .multilineTextAlignment(.center)

                Text(statusText)
                    .font(.system(size: pt(10)))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)

                Button {
                    bridge.requestRefresh()
                } label: {
                    Label(L("Refresh"), systemImage: "arrow.clockwise")
                        .font(.system(size: pt(11), weight: .semibold))
                }
                .buttonStyle(.borderedProminent)

                NavigationLink {
                    WatchSettingsView()
                } label: {
                    Label(L("Settings"), systemImage: "gearshape")
                        .font(.system(size: pt(10)))
                }
            }
            .padding(.horizontal, pt(6))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    WatchBrandMark(size: pt(18))
                }
            }
        }
    }
}

// MARK: - one chat, one screen: crown scrolls text, buttons stay put
