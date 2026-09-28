import SwiftUI
import WatchKit

struct WatchRootView: View {
    @StateObject private var bridge = WatchBridge.shared

    var body: some View {
        Group {
            rootContent
        }
        .onAppear { bridge.start() }
    }

    @ViewBuilder
    private var rootContent: some View {
#if DEBUG
        if ProcessInfo.processInfo.environment["GRANTTAP_WATCH_CAPTURE"] == "approval",
           let approval = bridge.state.approvals.first {
            ChatScreen(chat: WatchChat(from: approval))
        } else if ProcessInfo.processInfo.environment["GRANTTAP_WATCH_CAPTURE"] == "task",
                  let session = bridge.state.sessions.first(where: { $0.agent == "codex" }) {
            NavigationStack {
                SessionActivityView(session: session)
            }
        } else {
            standardRoot
        }
#else
        standardRoot
#endif
    }

    @ViewBuilder
    private var standardRoot: some View {
        if bridge.hasLiveData {
            NavigationStack {
                UnifiedTaskPage()
                    .navigationBarTitleDisplayMode(.inline)
            }
        } else {
            WatchSyncView()
        }
    }
}
