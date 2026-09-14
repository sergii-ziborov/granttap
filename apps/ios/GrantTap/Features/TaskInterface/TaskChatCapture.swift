import Foundation

extension TaskChatView {
    var suppressAvailabilityForDebugCapture: Bool {
        #if DEBUG
        ProcessInfo.processInfo.environment["GRANTTAP_CHAT_SCREENSHOT"] != nil
            || ProcessInfo.processInfo.environment["GRANTTAP_IMAGE_PREVIEW_SCREENSHOT"] != nil
        #else
        false
        #endif
    }

    @MainActor
    func focusComposerForDebugCapture() async {
        #if DEBUG
        guard ProcessInfo.processInfo.environment["GRANTTAP_FOCUS_COMPOSER"] != nil,
              ProcessInfo.processInfo.environment["GRANTTAP_IMAGE_PREVIEW_SCREENSHOT"] == nil
        else { return }
        try? await Task.sleep(nanoseconds: 500_000_000)
        chatFocused = true
        #endif
    }
}
