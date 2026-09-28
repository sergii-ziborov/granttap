import Foundation

/// Pure app-lock rules (mirrored by packages/core/security-lock-policy.ts).
enum SecurityLockPolicy {
    static let pinLength = 6
    static let allowedLockDelays: [TimeInterval] = [0, 30, 60]

    static func showsLockUI(
        enabled: Bool,
        locked: Bool,
        screen: SecurityGate.LockScreen
    ) -> Bool {
        if case .pinSetup = screen { return true }
        return enabled && locked
    }

    static func afterEnableAuth(hasPin: Bool) -> Bool {
        // true → applyEnabled; false → pinSetup
        hasPin
    }

    /// Stay unlocked after toggle auth so Settings can show the flipped switch.
    static func applyEnabledLeavesUnlocked() -> Bool { true }

    static func isValidPinFormat(_ pin: String) -> Bool {
        pin.count == pinLength && pin.allSatisfy(\.isNumber)
    }

    static func isAllowedLockDelay(_ seconds: TimeInterval) -> Bool {
        allowedLockDelays.contains(seconds)
    }

    /// Face ID is asked for on return, once per lock. The Face ID sheet flips
    /// the scene inactive and back, so a second ask from the same lock would
    /// loop; one ask, then the Unlock button, cannot.
    static func sceneActiveAutoUnlocks() -> Bool { true }

    static func healEnabledPref(storedEnabled: Bool, hasPin: Bool) -> Bool {
        storedEnabled && hasPin
    }

    static func cancelPinSetupLocks(wasEnable: Bool, enabled: Bool) -> Bool {
        if wasEnable && !enabled { return false }
        return enabled
    }
}
