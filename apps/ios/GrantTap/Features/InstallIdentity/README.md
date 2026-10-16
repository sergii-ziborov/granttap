# Install identity

Deleting an iOS app wipes its container but leaves its Keychain items in place.
Without this module a delete-and-reinstall from TestFlight or the App Store came
back with the previous install's paired computers, app lock PIN, member links,
and per-room session keys already present, while every UserDefaults-backed
routing table was gone. Half the state survived, which is worse than either end.

- `InstallIdentity.swift` decides which launch this is and reconciles the two
  copies of the install id. The Keychain copy survives deletion; the container
  copy does not, so a Keychain id with no container copy proves a reinstall.
- `InstallKeychain.swift` stores that id and purges every service under the
  `com.ziborov.granttap.` prefix. Session keys carry the room id in the service
  name, so the prefix is the only way to reach all of them.

An install that predates this module has no id anywhere. Its existing GrantTap
Application Support directory distinguishes an update from a delete/reinstall:
an update adopts and stamps an id without removing its pairing; a deleted old
build leaves only its owned Keychain secrets, so those are purged before the new
install starts. This also covers deleting Build 8 before first opening Build 9.

`AppDelegate` reconciles before it starts services, so `AppModel.start()` reads
the registry after any purge. See `GrantTapTests/Features/InstallIdentity`.

On Mac Catalyst a different defaults container is not evidence of deletion:
development and sandboxed distributions may share the Keychain. Mac launches
adopt the existing shared marker without rotating it or purging credentials.
This also keeps an older Mac build's matching marker valid. Isolated UI
fixtures skip live reconciliation entirely. Persistence tests use a dedicated
UserDefaults suite and Keychain service prefix, including the real round trip;
they never rewrite the installed app's identity record.
Adoption also preserves a surviving container marker when Keychain cannot be
read, so a temporary access failure cannot manufacture a reinstall on next launch.
