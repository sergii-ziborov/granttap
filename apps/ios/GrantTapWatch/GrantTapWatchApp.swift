import SwiftUI

/// watchOS companion. Live agent state arrives through the paired iPhone over
/// WatchConnectivity; the watch never manufactures sessions or approval data.
@main
struct GrantTapWatchApp: App {
    @AppStorage(AppLocale.storageKey) private var language = "en"

    var body: some Scene {
        WindowGroup {
            WatchRootView()
                .environment(\.locale, Locale(identifier: language))
        }
    }
}
