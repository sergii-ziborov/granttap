# Secure pairing

Pairing is split into the value model, network validation, QR/manual link
parsing, and Keychain storage.

- `PairingModel.swift` owns the paired-device value and secure mailbox fetch.
- `PairingValidation.swift` limits relay addresses and validates all secrets.
- `PairingLinks.swift` parses v2 mailbox links and migrates legacy v1 records.
- `Identity/SessionKeyVault.swift` stores per-task encryption keys.
- `Identity/PairingKeychain.swift` isolates the legacy Keychain adapter.
- `AccountBridge/` signs in with a synced passkey and recovers a computer through
  an account-authorized, end-to-end encrypted offer. The account session is
  stored only in this device's Keychain; QR pairing remains available.
- `Device/ControllerInviteCoordinator.swift` requests a separate, expiring
  controller credential from each Live linked computer. The trusted phone
  publishes their encrypted one-use links as a second QR through the relay.
  `ControllerNetworkTransfer.swift` opens that QR on a new iPhone or iPad and
  validates every computer before storing the new connections together.

`Device/ComputerLinkEnrollment.swift` opens a one-use computer link or an
iPhone device-network invitation and saves through the additive registry.
Network invitations save all computers together. It rejects Project and company invites.
`Device/ControllerEnrollment.swift` validates private local enrollment responses
for Mac Settings; leaving the page discards transfer material.

Controller transfer joins the person's device network. It does not grant any
Project Mesh membership. A failed partial transfer requires a fresh QR because
the relay mailboxes are single-use. The QR and its key must never be logged or
used in public screenshots.

See `GrantTapTests/AppRuntimeTests.swift` and the shared pairing tests for URI,
expiry, migration, and invalid-input coverage.
