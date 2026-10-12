# AccountBridge

[public source](https://github.com/sergii-ziborov/granttap) · Public entry: `AccountConnectionView.swift`

A passkey authenticates one Personal account, which contains many Project Meshes.
It does not select a computer or change a Task's route. A new passkey creates a
new account; the same passkey returns to the existing account. QR pairings stay
local until their Mac's MCP identity is verified; signing in on the phone does
not manufacture a second account machine for an old QR room.
When a passkey recovers the same Mac as an older QR room, its machine identity
replaces the stale QR credential. An old QR room with no recent chat catalog
is recovered automatically when account sync sees that Mac online and its
saved encrypted route has no fresh authenticated liveness evidence. A live
route keeps its phone key while the catalog is delayed. On startup the saved
route gets 30 seconds for its first handshake before automatic recovery may
issue another controller key; retries cannot extend that window. Explicit
Reconnect bypasses the window. The
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
