import SwiftUI

extension ContentView {
    /// Lock, privacy shield, and launch chrome sit above every tab.
    @ViewBuilder var privacyLayers: some View {
        if security.showsLockUI {
            SecurityLockView(security: security,
                             pendingCount: model.pending.count + model.questions.count
                                + model.meshNeedsYouEvents.count)
                .zIndex(10)
        }
        if security.enabled && security.obscured { SecurityPrivacyShield().zIndex(11) }
        if security.launching { GrantTapLaunchChrome().zIndex(20) }
    }
}
