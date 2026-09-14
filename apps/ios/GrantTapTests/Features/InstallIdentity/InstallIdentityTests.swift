import Security
import XCTest
@testable import GrantTap

/// iOS wipes the app container on delete but keeps Keychain items, so a
/// reinstall used to come back with the previous install's paired computers.
final class InstallIdentityTests: XCTestCase {
    private let ownPrefix = "com.ziborov.granttap.install-identity-tests."
    private let foreignService = "com.example.install-identity-tests.keep"

    override func tearDown() {
        OwnedKeychainItems.removeAll(prefix: ownPrefix)
        remove(service: foreignService, account: "keep")
        super.tearDown()
    }

    // MARK: Which launch is this

    func testNoIdStoredAnywhereIsAnAdoptionRatherThanAReinstall() {
        XCTAssertEqual(
            InstallIdentityLogic.state(
                keychainId: nil, containerId: nil,
                hasOwnedSecrets: false, hasLegacyContainerState: false
            ),
            .adopted
        )
        XCTAssertEqual(
            InstallIdentityLogic.state(
                keychainId: nil, containerId: "orphan",
                hasOwnedSecrets: false, hasLegacyContainerState: false
            ),
            .adopted
        )
    }

    func testMatchingIdsAreTheSameInstall() {
        XCTAssertEqual(
            InstallIdentityLogic.state(
                keychainId: "a", containerId: "a",
                hasOwnedSecrets: true, hasLegacyContainerState: true
            ),
            .unchanged
        )
    }

    func testAKeychainIdThatOutlivedTheContainerIsAReinstall() {
        XCTAssertEqual(
            InstallIdentityLogic.state(
                keychainId: "a", containerId: nil,
                hasOwnedSecrets: true, hasLegacyContainerState: false
            ),
            .reinstalled
        )
        XCTAssertEqual(
            InstallIdentityLogic.state(
                keychainId: "a", containerId: "b",
                hasOwnedSecrets: true, hasLegacyContainerState: true
            ),
            .reinstalled
        )
    }

    func testDeletingALegacyBuildIsDetectedFromItsOrphanedSecrets() {
        XCTAssertEqual(
            InstallIdentityLogic.state(
                keychainId: nil, containerId: nil,
                hasOwnedSecrets: true, hasLegacyContainerState: false
            ),
            .reinstalled
        )
    }

    func testUpdatingALegacyBuildKeepsPairingWhenItsContainerSurvived() {
        XCTAssertEqual(
            InstallIdentityLogic.state(
                keychainId: nil, containerId: nil,
                hasOwnedSecrets: true, hasLegacyContainerState: true
            ),
            .adopted
        )
    }

    // MARK: What reconcile does

    func testUpdatingAnExistingInstallStampsAnIdAndKeepsItsSecrets() {
        let probe = Probe(
            keychainId: nil, containerId: nil,
            hasOwnedSecrets: true, hasLegacyContainerState: true
        )
        XCTAssertEqual(InstallIdentity.reconcile(stores: probe.stores), .adopted)
        XCTAssertEqual(probe.purges, 0)
        XCTAssertEqual(probe.written, ["fresh"])
    }

    func testAnOrdinaryLaunchTouchesNeitherStore() {
        let probe = Probe(keychainId: "same", containerId: "same")
        XCTAssertEqual(InstallIdentity.reconcile(stores: probe.stores), .unchanged)
        XCTAssertEqual(probe.purges, 0)
        XCTAssertTrue(probe.written.isEmpty)
    }

    func testAReinstallPurgesOwnedSecretsBeforeStampingTheNewInstall() {
        let probe = Probe(keychainId: "old", containerId: nil)
        XCTAssertEqual(InstallIdentity.reconcile(stores: probe.stores), .reinstalled)
        XCTAssertEqual(probe.purges, 1)
        XCTAssertEqual(probe.written, ["fresh"])
        XCTAssertEqual(probe.order, ["purge", "write"])
    }

    func testDeletingALegacyBuildAlsoPurgesBeforeStampingTheNewInstall() {
        let probe = Probe(
            keychainId: nil, containerId: nil,
            hasOwnedSecrets: true, hasLegacyContainerState: false
        )
        XCTAssertEqual(InstallIdentity.reconcile(stores: probe.stores), .reinstalled)
        XCTAssertEqual(probe.purges, 1)
        XCTAssertEqual(probe.order, ["purge", "write"])
    }

    // MARK: Durable Keychain state

    func testPurgeRemovesEveryOwnedServiceIncludingPerRoomSessionKeys() {
        let connections = ownPrefix + "connections"
        let sessionKeys = ownPrefix + "session-keys.room-42"
        store("mac", service: connections, account: "linked-computers")
        store("key", service: sessionKeys, account: "task-keys")
        XCTAssertEqual(OwnedKeychainItems.services(prefix: ownPrefix), [connections, sessionKeys].sorted())

        OwnedKeychainItems.removeAll(prefix: ownPrefix)

        XCTAssertTrue(OwnedKeychainItems.services(prefix: ownPrefix).isEmpty)
        XCTAssertNil(read(service: connections, account: "linked-computers"))
        XCTAssertNil(read(service: sessionKeys, account: "task-keys"))
    }

    func testPurgeRemovesEveryAccountUnderOneService() {
        let pin = ownPrefix + "pin"
        store("hash", service: pin, account: "app-lock-pin")
        store("salt", service: pin, account: "app-lock-pin-salt")

        OwnedKeychainItems.removeAll(prefix: ownPrefix)

        XCTAssertNil(read(service: pin, account: "app-lock-pin"))
        XCTAssertNil(read(service: pin, account: "app-lock-pin-salt"))
    }

    func testPurgeLeavesServicesOutsideThePrefixAlone() {
        store("mine", service: ownPrefix + "connections", account: "linked-computers")
        store("theirs", service: foreignService, account: "keep")

        OwnedKeychainItems.removeAll(prefix: ownPrefix)

        XCTAssertEqual(read(service: foreignService, account: "keep"), "theirs")
    }

    func testTheShippedPrefixCoversEveryServiceTheAppWritesTo() {
        for service in [
            "com.ziborov.granttap.connections", "com.ziborov.granttap.pairing",
            "com.ziborov.granttap.pin", "com.ziborov.granttap.member-links",
            "com.ziborov.granttap.grok-bot-mesh", "com.ziborov.granttap.session-keys.room",
            InstallIdentity.service,
        ] {
            XCTAssertTrue(service.hasPrefix(OwnedKeychainItems.servicePrefix), service)
        }
    }

    func testTheLiveStoresRoundTripAnIdThroughBothCopiesContainerFirst() {
        let stores = InstallIdentityStores.live
        let previousContainer = stores.containerId()
        let previousKeychain = stores.keychainId()
        defer { restore(container: previousContainer, keychain: previousKeychain) }

        stores.writeId("round-trip")

        XCTAssertEqual(stores.containerId(), "round-trip")
        XCTAssertEqual(stores.keychainId(), "round-trip")
        XCTAssertNotEqual(stores.newId(), stores.newId())
    }

    // MARK: Helpers

    private final class Probe {
        private(set) var purges = 0
        private(set) var written: [String] = []
        private(set) var order: [String] = []
        let stores: InstallIdentityStores

        init(
            keychainId: String?, containerId: String?,
            hasOwnedSecrets: Bool = true, hasLegacyContainerState: Bool = false
        ) {
            var record: (purge: () -> Void, write: (String) -> Void)?
            stores = InstallIdentityStores(
                keychainId: { keychainId }, containerId: { containerId },
                hasOwnedSecrets: { hasOwnedSecrets },
                hasLegacyContainerState: { hasLegacyContainerState },
                writeId: { record?.write($0) }, purgeOwnedSecrets: { record?.purge() },
                newId: { "fresh" }
            )
            record = (
                purge: { [weak self] in self?.purges += 1; self?.order.append("purge") },
                write: { [weak self] id in self?.written.append(id); self?.order.append("write") }
            )
        }
    }

    private func restore(container: String?, keychain: String?) {
        if let container {
            UserDefaults.standard.set(container, forKey: InstallIdentity.containerKey)
        } else {
            UserDefaults.standard.removeObject(forKey: InstallIdentity.containerKey)
        }
        if let keychain {
            InstallIdentityRecord.save(keychain)
        } else {
            remove(service: InstallIdentity.service, account: InstallIdentity.account)
        }
    }

    private func store(_ value: String, service: String, account: String) {
        remove(service: service, account: account)
        let item: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecValueData as String: Data(value.utf8),
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
        ]
        XCTAssertEqual(SecItemAdd(item as CFDictionary, nil), errSecSuccess, service)
    }

    private func read(service: String, account: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data else { return nil }
        return String(decoding: data, as: UTF8.self)
    }

    private func remove(service: String, account: String) {
        SecItemDelete([
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ] as CFDictionary)
    }
}
