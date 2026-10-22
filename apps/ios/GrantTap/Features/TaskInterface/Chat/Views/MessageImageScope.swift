import SwiftUI

private struct MessageImageSessionKey: EnvironmentKey {
    static let defaultValue: String? = nil
}

extension EnvironmentValues {
    var messageImageSessionId: String? {
        get { self[MessageImageSessionKey.self] }
        set { self[MessageImageSessionKey.self] = newValue }
    }
}
