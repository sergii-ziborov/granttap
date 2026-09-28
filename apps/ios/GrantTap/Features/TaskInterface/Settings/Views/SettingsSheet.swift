import SwiftUI

/// Phone and tablet presentation of the same Settings content used as a Mac page.
struct SettingsSheet: View {
    @Environment(\.dismiss) private var dismiss
    var modelOverride: AppModel? = nil
    var localComputer: String? = nil
    var localPaired: Bool? = nil
    var localRelayStatus: String? = nil
    var localPhoneReachability: String? = nil

    var body: some View {
        CompatNavigationStack {
            SettingsView(
                modelOverride: modelOverride, localComputer: localComputer,
                localPaired: localPaired, localRelayStatus: localRelayStatus,
                localPhoneReachability: localPhoneReachability,
                onExitDemo: { dismiss() }
            )
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(L("Done")) { dismiss() }
                }
            }
        }
    }
}
