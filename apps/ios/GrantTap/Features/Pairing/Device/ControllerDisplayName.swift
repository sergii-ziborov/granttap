import Foundation
import UIKit

/// The user's visible controller label; iOS can expose only a generic device
/// name without Apple's separately approved user-assigned-name entitlement.
enum ControllerDisplayName {
    private static let key = "granttap.controller-display-name"

    static func current(store: UserDefaults = .standard, systemName: String? = nil) -> String {
        let native = systemName ?? UIDevice.current.name
        return valid(store.string(forKey: key)) ?? valid(native) ?? "iPhone"
    }

    @discardableResult
    static func save(_ proposed: String, store: UserDefaults = .standard) -> Bool {
        guard let name = valid(proposed) else { return false }
        store.set(name, forKey: key)
        return true
    }

    private static func valid(_ value: String?) -> String? {
        let name = value?.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let name, !name.isEmpty, name.count <= 80,
              name.rangeOfCharacter(from: .controlCharacters) == nil else { return nil }
        return name
    }
}
