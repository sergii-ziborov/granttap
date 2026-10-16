import Foundation

enum InstallIdentityPlatform: Equatable {
    case iOS, macCatalyst
    static var current: Self {
        #if targetEnvironment(macCatalyst)
        return .macCatalyst
        #else
        return .iOS
        #endif
    }
}

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
        hasOwnedSecrets: Bool, hasLegacyContainerState: Bool,
        platform: InstallIdentityPlatform = .iOS
    ) -> InstallState {
        // Mac development and sandboxed distributions can have distinct
        // defaults containers while sharing Keychain state. That is not proof
        // of deletion and must never erase an existing local/account grant.
        if platform == .macCatalyst {
            return keychainId != nil && keychainId == containerId ? .unchanged : .adopted
        }
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
    var platform: InstallIdentityPlatform = .iOS

    static let live = persisted(defaults: .standard, service: InstallIdentity.service,
                                prefix: OwnedKeychainItems.servicePrefix)

    static func persisted(defaults: UserDefaults, service: String, prefix: String,
                          platform: InstallIdentityPlatform = .current) -> Self {
        Self(
        keychainId: { InstallIdentityRecord.load(service: service) },
        containerId: { defaults.string(forKey: InstallIdentity.containerKey) },
        hasOwnedSecrets: {
            OwnedKeychainItems.services(prefix: prefix).contains { $0 != service }
        },
        hasLegacyContainerState: { InstallIdentity.legacySupportDirectoryExists() },
        writeId: { id in
            // Container copy first, and only stamp the Keychain once it reads
            // back. Dying between the two writes then leaves a container id
            // with no Keychain copy, which adopts on the next launch. The
            // other order would report a reinstall and purge a healthy install.
            defaults.set(id, forKey: InstallIdentity.containerKey)
            guard defaults.string(forKey: InstallIdentity.containerKey) == id else { return }
            InstallIdentityRecord.save(id, service: service)
        },
        purgeOwnedSecrets: { OwnedKeychainItems.removeAll(prefix: prefix) },
        newId: { UUID().uuidString }, platform: platform
        )
    }
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
        let keychainId = stores.keychainId()
        let containerId = stores.containerId()
        let state = InstallIdentityLogic.state(
            keychainId: keychainId, containerId: containerId,
            hasOwnedSecrets: stores.hasOwnedSecrets(),
            hasLegacyContainerState: stores.hasLegacyContainerState(), platform: stores.platform
        )
        switch state {
        case .unchanged:
            return state
        case .reinstalled:
            stores.purgeOwnedSecrets()
        case .adopted:
            break
        }
        // Adoption keeps any surviving marker, including when Keychain is
        // temporarily unreadable. A new marker could make another build
        // mistake a healthy installation for deletion when access returns.
        let id = state == .adopted ? keychainId ?? containerId ?? stores.newId() : stores.newId()
        stores.writeId(id)
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
