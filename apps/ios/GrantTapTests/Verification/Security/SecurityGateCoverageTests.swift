import SwiftUI
import XCTest
import LocalAuthentication
@testable import GrantTap

@MainActor
final class SecurityGateCoverageTests: XCTestCase {
    private let enabledKey = "granttap.security.device-owner-auth"

    override func setUp() {
        UserDefaults.standard.set(false, forKey: enabledKey)
        UserDefaults.standard.removeObject(forKey: SecurityGate.lockDelayKey)
        AppPinStore.clear()
    }

    override func tearDown() {
        UserDefaults.standard.set(false, forKey: enabledKey)
        UserDefaults.standard.removeObject(forKey: SecurityGate.lockDelayKey)
        AppPinStore.clear()
    }

    func testEnablePinSetupLockLifecycleAndDisable() {
        // Enable, the automatic ask on return (cancelled), disable.
        let auth = AuthenticatorStub(results: [.success, .failure("Cancelled"), .success])
        let gate = SecurityGate(authenticator: auth)
        XCTAssertEqual(gate.biometryName, "Test ID")
        XCTAssertFalse(gate.enabled)
        XCTAssertFalse(gate.showsLockUI)

        gate.setEnabled(true)
        XCTAssertEqual(gate.lockScreen, .pinSetup(confirming: false))
        XCTAssertTrue(gate.locked)
        XCTAssertTrue(gate.showsLockUI)
        XCTAssertFalse(gate.completePinSetupDigit("123"))
        XCTAssertTrue(gate.completePinSetupDigit("123456"))
        XCTAssertEqual(gate.lockScreen, .pinSetup(confirming: true))
        XCTAssertFalse(gate.completePinSetupDigit("654321"))
        XCTAssertNotNil(gate.errorText)
        XCTAssertTrue(gate.completePinSetupDigit("123456"))
        XCTAssertTrue(gate.completePinSetupDigit("123456"))
        XCTAssertTrue(gate.enabled)
        XCTAssertFalse(gate.locked)
        XCTAssertTrue(AppPinStore.verify("123456"))

        gate.sceneChanged(.inactive)
        gate.sceneChanged(.background)
        XCTAssertTrue(gate.locked)
        XCTAssertTrue(gate.obscured)
        gate.sceneChanged(.active)
        XCTAssertTrue(gate.locked, "Face ID was asked for once and cancelled; the gate stays down")
        XCTAssertFalse(gate.obscured)
        XCTAssertEqual(auth.reasons.count, 2, "one automatic ask on return")
        gate.sceneChanged(.inactive)
        gate.sceneChanged(.active)
        XCTAssertEqual(auth.reasons.count, 2, "the Face ID sheet flipping the scene does not ask again")
        gate.beginPinEntry()
        XCTAssertEqual(gate.lockScreen, .pinEntry)
        XCTAssertFalse(gate.unlockWithPin("000000"))
        XCTAssertTrue(gate.unlockWithPin("123456"))
        XCTAssertFalse(gate.locked)

        gate.setLockDelay(7)
        XCTAssertEqual(gate.lockDelay, 0)
        gate.setLockDelay(60)
        XCTAssertEqual(gate.lockDelay, 60)
        gate.setEnabled(false)
        XCTAssertFalse(gate.enabled)
        XCTAssertEqual(auth.reasons.count, 3)
    }

    func testChangePinCancelAndBiometryResultPaths() {
        XCTAssertTrue(AppPinStore.save("123456"))
        UserDefaults.standard.set(true, forKey: enabledKey)
        let auth = AuthenticatorStub(results: [
            .success, .success, .unavailable("No sensor"),
            .failure("Cancelled"), .success,
        ])
        let gate = SecurityGate(authenticator: auth)
        XCTAssertTrue(gate.enabled)
        XCTAssertTrue(gate.locked)

        gate.beginChangePin()
        XCTAssertEqual(gate.lockScreen, .pinSetup(confirming: false))
        XCTAssertTrue(gate.completePinSetupDigit("654321"))
        XCTAssertTrue(gate.completePinSetupDigit("654321"))
        XCTAssertTrue(AppPinStore.verify("654321"))
        XCTAssertFalse(gate.locked)

        gate.sceneChanged(.background)
        gate.beginChangePin()
        gate.cancelPinSetup()
        XCTAssertTrue(gate.locked)
        XCTAssertEqual(gate.lockScreen, .unlock)

        gate.unlockWithBiometry()
        XCTAssertEqual(gate.errorText, "No sensor")
        XCTAssertEqual(gate.lockScreen, .pinEntry)
        gate.cancelPinEntry()
        gate.unlock()
        XCTAssertEqual(gate.errorText, "Cancelled")
        XCTAssertTrue(gate.locked)
        gate.unlockWithBiometry()
        XCTAssertFalse(gate.locked)
        XCTAssertNil(gate.errorText)
    }

    func testCancellingFirstPinSetupLeavesTheDisabledGateUnlocked() {
        let gate = SecurityGate(authenticator: AuthenticatorStub(results: [.success]))
        gate.setEnabled(true)
        gate.cancelPinSetup()
        XCTAssertFalse(gate.enabled)
        XCTAssertFalse(gate.locked)
        XCTAssertEqual(gate.lockScreen, .unlock)
        gate.beginPinEntry()
        XCTAssertFalse(gate.unlockWithPin("123456"))
        gate.sceneChanged(.background)
        XCTAssertFalse(gate.obscured)
    }

    func testLocalAuthenticatorReportsUnavailableSuccessAndFailureFromItsContext() async {
        let unavailableContext = DeviceAuthContextStub(
            canEvaluate: [false, false], success: false,
            error: NSError(domain: "auth", code: 1,
                           userInfo: [NSLocalizedDescriptionKey: "Unavailable"])
        )
        let unavailable = LocalDeviceOwnerAuthenticator { unavailableContext }
        let unavailableResult = await authenticate(unavailable)
        XCTAssertEqual(unavailableResult, .unavailable("Unavailable"))

        let successContext = DeviceAuthContextStub(canEvaluate: [true, true], success: true)
        let success = LocalDeviceOwnerAuthenticator { successContext }
        let successResult = await authenticate(success)
        XCTAssertEqual(successResult, .success)
        XCTAssertEqual(successContext.reason, "Coverage authentication")

        let failure = NSError(
            domain: "auth", code: 2,
            userInfo: [NSLocalizedDescriptionKey: "Cancelled"]
        )
        let failedContext = DeviceAuthContextStub(
            canEvaluate: [false, true], success: false, error: failure
        )
        let failed = LocalDeviceOwnerAuthenticator { failedContext }
        let failureResult = await authenticate(failed)
        XCTAssertEqual(failureResult, .failure("Cancelled"))
    }

    private func authenticate(
        _ authenticator: LocalDeviceOwnerAuthenticator
    ) async -> DeviceOwnerAuthResult {
        await withCheckedContinuation { continuation in
            authenticator.authenticate(reason: "Coverage authentication") {
                continuation.resume(returning: $0)
            }
        }
    }
}

private final class DeviceAuthContextStub: LAContext {
    var results: [Bool]
    let success: Bool
    let resultError: NSError?
    var reason: String?

    init(canEvaluate: [Bool], success: Bool, error: NSError? = nil) {
        results = canEvaluate
        self.success = success
        resultError = error
        super.init()
    }

    override func canEvaluatePolicy(
        _ policy: LAPolicy,
        error: NSErrorPointer
    ) -> Bool {
        let result = results.isEmpty ? false : results.removeFirst()
        if !result { error?.pointee = resultError }
        return result
    }

    override func evaluatePolicy(
        _ policy: LAPolicy, localizedReason: String,
        reply: @escaping (Bool, (any Error)?) -> Void
    ) {
        reason = localizedReason
        reply(success, resultError)
    }
}

@MainActor
private final class AuthenticatorStub: DeviceOwnerAuthenticating {
    let biometryName = "Test ID"
    var results: [DeviceOwnerAuthResult]
    var reasons: [String] = []

    init(results: [DeviceOwnerAuthResult]) {
        self.results = results
    }

    func authenticate(
        reason: String,
        completion: @escaping @MainActor (DeviceOwnerAuthResult) -> Void
    ) {
        reasons.append(reason)
        completion(results.isEmpty ? .failure("No result") : results.removeFirst())
    }
}
