import Foundation
import SwiftUI

@MainActor
final class SecurityGate: ObservableObject {
    static let shared = SecurityGate()
    private static let enabledKey = "granttap.security.device-owner-auth"
    static let lockDelayKey = "granttap.security.lock-delay"

    enum LockScreen: Equatable {
        case unlock
        case pinEntry
        case pinSetup(confirming: Bool)
    }

    @Published private(set) var enabled: Bool
    @Published private(set) var locked: Bool {
        didSet { if !locked { autoPromptedForLock = false } }
    }
    /// Face ID has been asked for since this lock came down; a failed or
    /// cancelled ask leaves the Unlock button, not another ask.
    private var autoPromptedForLock = false
    @Published private(set) var authenticating = false
    @Published private(set) var lockScreen: LockScreen = .unlock
    @Published var errorText: String?
    @Published private(set) var lockDelay: TimeInterval
    @Published private(set) var obscured = false
    /// Brief unified chrome on every cold start (Face ID on or off).
    @Published private(set) var launching = true
    private var backgroundedAt: Date?
    private var pendingPin: String?
    private var pinSetupForEnable = false
    private var pinSetupForChange = false
    private let authenticator: DeviceOwnerAuthenticating

    convenience init() {
        self.init(authenticator: LocalDeviceOwnerAuthenticator())
    }

    init(authenticator: DeviceOwnerAuthenticating) {
        self.authenticator = authenticator
        let stored = UserDefaults.standard.bool(forKey: Self.enabledKey)
        // App lock requires a GrantTap PIN — heal stale prefs from older builds.
        let isEnabled = SecurityLockPolicy.healEnabledPref(
            storedEnabled: stored, hasPin: AppPinStore.isSet)
        if stored && !isEnabled {
            UserDefaults.standard.set(false, forKey: Self.enabledKey)
        }
        enabled = isEnabled
        locked = isEnabled
        lockDelay = UserDefaults.standard.object(forKey: Self.lockDelayKey) == nil
            ? 0 : UserDefaults.standard.double(forKey: Self.lockDelayKey)
        Task { @MainActor in
            #if DEBUG
            // Demo / screenshot launches must clear chrome quickly for sim verification.
            let demoFast = ProcessInfo.processInfo.environment["GRANTTAP_DEMO"] == "1"
                || ProcessInfo.processInfo.environment["GRANTTAP_OPEN_SESSION"] != nil
            try? await Task.sleep(nanoseconds: demoFast ? 150_000_000 : 700_000_000)
            #else
            try? await Task.sleep(nanoseconds: 700_000_000)
            #endif
            self.launching = false
        }
    }

    var biometryName: String {
        authenticator.biometryName
    }

    var hasPin: Bool { AppPinStore.isSet }

    /// Lock / PIN chrome — including first-time PIN setup before `enabled` flips.
    var showsLockUI: Bool {
        SecurityLockPolicy.showsLockUI(enabled: enabled, locked: locked, screen: lockScreen)
    }

    func setEnabled(_ desired: Bool) {
        guard desired != enabled, !authenticating else { return }
        if desired {
            // Confirm device owner, then require GrantTap PIN before enabling.
            authenticateBiometry(reason: L("Protect GrantTap tasks and approvals.")) { [weak self] success in
                guard let self, success else { return }
                if SecurityLockPolicy.afterEnableAuth(hasPin: AppPinStore.isSet) {
                    self.applyEnabled(true)
                } else {
                    self.pinSetupForEnable = true
                    self.pinSetupForChange = false
                    self.pendingPin = nil
                    self.lockScreen = .pinSetup(confirming: false)
                    // Keep enabled=false until PIN is saved — showsLockUI still
                    // presents pinSetup so setup is reachable above Settings.
                    self.locked = true
                    self.errorText = nil
                }
            }
            return
        }
        authenticateBiometry(reason: L("Confirm turning off the GrantTap app lock.")) { [weak self] success in
            guard let self, success else { return }
            self.applyEnabled(false)
        }
    }

    /// Settings → Change PIN (lock stays on).
    func beginChangePin() {
        guard enabled, !authenticating else { return }
        authenticateBiometry(reason: L("Confirm changing your GrantTap PIN.")) { [weak self] success in
            guard let self, success else { return }
            self.pinSetupForChange = true
            self.pinSetupForEnable = false
            self.pendingPin = nil
            self.lockScreen = .pinSetup(confirming: false)
            self.locked = true
            self.errorText = nil
        }
    }

    func sceneChanged(_ phase: ScenePhase) {
        // Never call unlockWithBiometry() from .active — Face ID loops
        // (SecurityLockPolicy.sceneActiveAutoUnlocks() == false).
        guard enabled else { locked = false; obscured = false; return }
        switch phase {
        case .inactive:
            // Sheet / Control Center can flip inactive without leaving the app.
            // Do NOT obscure or lock here — that looked like "opening a chat
            // immediately locks the iPhone".
            break
        case .background:
            obscured = true
            if backgroundedAt == nil { backgroundedAt = Date() }
            if lockDelay <= 0 {
                locked = true
                if lockScreen != .pinSetup(confirming: false) &&
                    lockScreen != .pinSetup(confirming: true) {
                    lockScreen = .unlock
                }
            }
        case .active:
            if let backgroundedAt,
               Date().timeIntervalSince(backgroundedAt) >= lockDelay {
                locked = true
                if case .pinSetup = lockScreen { /* keep setup */ }
                else { lockScreen = .unlock }
            }
            self.backgroundedAt = nil
            obscured = false
            // Ask for Face ID on the way back in, once: the ask itself flips
            // the scene inactive and active again, and that must not ask twice.
            if SecurityLockPolicy.sceneActiveAutoUnlocks(), locked, !autoPromptedForLock,
               !authenticating, case .unlock = lockScreen {
                autoPromptedForLock = true
                unlockWithBiometry()
            }
        @unknown default:
            break
        }
    }

    func setLockDelay(_ seconds: TimeInterval) {
        guard SecurityLockPolicy.isAllowedLockDelay(seconds) else { return }
        lockDelay = seconds
        UserDefaults.standard.set(seconds, forKey: Self.lockDelayKey)
        AuditStore.shared.record("security", detail: "App lock delay set to \(Int(seconds)) seconds")
    }

    /// The Unlock button, and the one automatic ask on return.
    func unlockWithBiometry() {
        guard enabled, locked, !authenticating else { return }
        guard case .unlock = lockScreen else { return }
        authenticateBiometry(reason: L("Unlock GrantTap tasks and approvals.")) { [weak self] success in
            guard let self else { return }
            if success {
                self.locked = false
                self.lockScreen = .unlock
                self.errorText = nil
            }
            AuditStore.shared.record(
                "unlock",
                detail: success ? "Biometry authenticated" : "Biometry failed",
                outcome: success ? "ok" : "failed"
            )
        }
    }

    /// Legacy alias used by older call sites / tests — same as Face ID tap.
    func unlock() { unlockWithBiometry() }

    func beginPinEntry() {
        guard enabled, locked, AppPinStore.isSet else { return }
        errorText = nil
        lockScreen = .pinEntry
    }

    func cancelPinEntry() {
        errorText = nil
        lockScreen = .unlock
    }

    @discardableResult
    func unlockWithPin(_ pin: String) -> Bool {
        guard enabled, locked else { return false }
        guard AppPinStore.verify(pin) else {
            errorText = L("Incorrect PIN")
            AuditStore.shared.record("unlock", detail: "PIN failed", outcome: "failed")
            return false
        }
        locked = false
        lockScreen = .unlock
        errorText = nil
        AuditStore.shared.record("unlock", detail: "PIN authenticated", outcome: "ok")
        return true
    }

    func cancelPinSetup() {
        pendingPin = nil
        let wasEnable = pinSetupForEnable
        pinSetupForEnable = false
        pinSetupForChange = false
        lockScreen = .unlock
        errorText = nil
        locked = SecurityLockPolicy.cancelPinSetupLocks(wasEnable: wasEnable, enabled: enabled)
    }

    @discardableResult
    func completePinSetupDigit(_ pin: String) -> Bool {
        guard SecurityLockPolicy.isValidPinFormat(pin) else { return false }
        if pendingPin == nil {
            pendingPin = pin
            lockScreen = .pinSetup(confirming: true)
            errorText = nil
            return true
        }
        guard pendingPin == pin else {
            pendingPin = nil
            lockScreen = .pinSetup(confirming: false)
            errorText = L("PINs did not match. Try again.")
            return false
        }
        guard AppPinStore.save(pin) else {
            errorText = L("Could not save PIN.")
            pendingPin = nil
            lockScreen = .pinSetup(confirming: false)
            return false
        }
        pendingPin = nil
        let enabling = pinSetupForEnable
        let changing = pinSetupForChange
        pinSetupForEnable = false
        pinSetupForChange = false
        lockScreen = .unlock
        errorText = nil
        if enabling { applyEnabled(true) }
        else if changing {
            locked = false
            AuditStore.shared.record("security", detail: "App lock PIN changed")
        }
        return true
    }

    private func applyEnabled(_ desired: Bool) {
        enabled = desired
        // Caller just authenticated (Face ID / PIN). Stay unlocked so Settings
        // can show the toggle flipped — next background still locks via sceneChanged.
        locked = !SecurityLockPolicy.applyEnabledLeavesUnlocked() ? desired : false
        lockScreen = .unlock
        UserDefaults.standard.set(desired, forKey: Self.enabledKey)
        AuditStore.shared.record("security", detail: desired ? "App lock enabled" : "App lock disabled")
    }

    private func authenticateBiometry(reason: String, completion: @escaping (Bool) -> Void) {
        authenticating = true
        errorText = nil
        authenticator.authenticate(reason: reason) { [weak self] result in
            guard let self else { return }
            self.authenticating = false
            switch result {
            case .success:
                completion(true)
            case .failure(let message):
                self.errorText = message
                completion(false)
            case .unavailable(let message):
                self.errorText = message ?? L("Face ID is unavailable. Use PIN.")
                if self.enabled, self.locked, AppPinStore.isSet {
                    self.lockScreen = .pinEntry
                }
                completion(false)
            }
        }
    }
}
