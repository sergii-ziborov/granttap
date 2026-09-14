# Secure pairing

Pairing is split into the value model, network validation, QR/manual link
parsing, and Keychain storage.

- `PairingModel.swift` owns the paired-device value and secure mailbox fetch.
- `PairingValidation.swift` limits relay addresses and validates all secrets.
- `PairingLinks.swift` parses v2 mailbox links and migrates legacy v1 records.
- `SessionKeyVault.swift` stores per-task encryption keys.
- `PairingKeychain.swift` isolates the legacy Keychain adapter.

See `GrantTapTests/AppRuntimeTests.swift` and the shared pairing tests for URI,
expiry, migration, and invalid-input coverage.
