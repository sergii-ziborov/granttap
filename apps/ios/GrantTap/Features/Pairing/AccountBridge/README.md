# AccountBridge

[Engineering index](../../../../../../AGENTS.md) · Public entry: `AccountConnectionView.swift`

A passkey authenticates one Personal account, which contains many Project Meshes.
It does not select a computer or change a Task's route. A new passkey creates a
new account; the same passkey returns to the existing account. QR pairings on the
device are linked to that account only after authentication, without replacing
their relay rooms.
When a passkey recovers the same Mac as an older QR room, its machine identity
replaces the stale QR credential. An old QR room with no recent chat catalog
is recovered automatically when account sync sees that Mac online. The
encrypted offer refreshes the phone key in the existing room; successful
recovery retires the QR credential so relaunches do not issue more keys.
Reconnect can request another offer if that route needs repair.

`AccountSpaceSync.swift` discovers the account's online computers in bounded
pages and requests fresh, end-to-end encrypted pairing offers in small batches.
The account service stores no pairing keys. Recovered links preserve the
account's machine identity in `AccountMachineReference.swift`, while the
machine token remains on the computer. Each Project snapshot and Task still
arrives from its original computer and retains that computer's route.

Tests live in `GrantTapTests/Verification/Device/AccountMachinePagingTests.swift`,
`AccountSpaceSyncTests.swift`, and `AccountRecoveryTests.swift`. Native passkey
registration and assertion require signed hardware and the associated domain.
