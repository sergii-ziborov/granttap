import Foundation

/// Which launch this is, decided from the two copies of the install id.
enum InstallState: Equatable {
    /// No id stored yet. An install that predates this build must keep the
    /// pairing it already has, so this stamps an id and purges nothing.
    case adopted
    /// Both copies present and equal: an ordinary launch.
    case unchanged
    /// The Keychain copy outlived a wiped container, which happens only when
    /// the app was deleted and installed again.
    case reinstalled
}

enum InstallIdentityLogic {
    static func state(
        keychainId: String?, containerId: String?,
        hasOwnedSecrets: Bool, hasLegacyContainerState: Bool
    ) -> InstallState {
        guard let keychainId else {
            // Builds shipped before install ids existed. Their App Support
            // directory survives an update, while deletion removes it and
            // leaves the old pairing secrets behind in Keychain.
            let legacyReinstall = containerId == nil
                && hasOwnedSecrets && !hasLegacyContainerState
            return legacyReinstall ? .reinstalled : .adopted
        }
        guard let containerId, containerId == keychainId else { return .reinstalled }
        return .unchanged
    }
}

/// The boundaries `reconcile` writes through, shaped like
/// `AppLifecycleDependencies` so tests drive real behavior without the Keychain.
struct InstallIdentityStores {
    var keychainId: () -> String?
    var containerId: () -> String?
    var hasOwnedSecrets: () -> Bool
    var hasLegacyContainerState: () -> Bool
    var writeId: (String) -> Void
    var purgeOwnedSecrets: () -> Void
    var newId: () -> String

    static let live = InstallIdentityStores(
        keychainId: { InstallIdentityRecord.load() },
        containerId: { UserDefaults.standard.string(forKey: InstallIdentity.containerKey) },
        hasOwnedSecrets: {
            OwnedKeychainItems.services().contains { $0 != InstallIdentity.service }
        },
        hasLegacyContainerState: { InstallIdentity.legacySupportDirectoryExists() },
        writeId: { id in
            // Container copy first, and only stamp the Keychain once it reads
            // back. Dying between the two writes then leaves a container id
            // with no Keychain copy, which adopts on the next launch. The
            // other order would report a reinstall and purge a healthy install.
            let defaults = UserDefaults.standard
            defaults.set(id, forKey: InstallIdentity.containerKey)
            guard defaults.string(forKey: InstallIdentity.containerKey) == id else { return }
            InstallIdentityRecord.save(id)
        },
        purgeOwnedSecrets: { OwnedKeychainItems.removeAll() },
        newId: { UUID().uuidString }
    )
}

/// iOS deletes the app container when the app is deleted but keeps Keychain
/// items, so paired computers, the app lock PIN, member links, and per-room
/// session keys used to come back after a delete and reinstall from TestFlight
/// or the App Store. Only the container copy of the install id dies with the
/// app, so a Keychain id without a matching container copy proves a reinstall.
enum InstallIdentity {
    static let containerKey = "granttap.install-id"
    static let service = "com.ziborov.granttap.install"
    static let account = "install-id"

    @discardableResult
    static func reconcile(stores: InstallIdentityStores = .live) -> InstallState {
        let state = InstallIdentityLogic.state(
            keychainId: stores.keychainId(), containerId: stores.containerId(),
            hasOwnedSecrets: stores.hasOwnedSecrets(),
            hasLegacyContainerState: stores.hasLegacyContainerState()
        )
        switch state {
        case .unchanged:
            return state
        case .reinstalled:
            stores.purgeOwnedSecrets()
        case .adopted:
            break
        }
        stores.writeId(stores.newId())
        return state
    }

    static func legacySupportDirectoryExists(fileManager: FileManager = .default) -> Bool {
        guard let root = fileManager.urls(
            for: .applicationSupportDirectory, in: .userDomainMask
        ).first else { return false }
        return fileManager.fileExists(
            atPath: root.appendingPathComponent("GrantTap", isDirectory: true).path
        )
    }
}
