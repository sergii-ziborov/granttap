# Connection health

This feature separates honest machine freshness from the phone WebSocket state.
`ConnectionSnapshot.swift` defines the phases, `AppModelConnectionHealth.swift`
derives them from authenticated room state, and `SettingsConnectionSection.swift`
renders per-computer QR, reconnect, and unlink controls. `DevicesView.swift`
owns the Devices destination after Usage. It shows the Account Mesh before any
computer is linked, followed by the account's device roster and optional local
connection controls. A Project Mesh and each Task retain their own route.

Connection routing and multi-computer regressions live in
`GrantTapTests/AppRuntimeTests.swift`.

`ProviderHookReviewView` shows native Codex hook trust for a selected computer.
A person reviews the full command and hash before confirming one definition.
The request targets that computer and hash; the client accepts success only
from the matching room, endpoint, and request with the same enabled, trusted
native definition. Timeout, modified definitions, and unavailable status do
not claim success. Tests live in `GrantTapTests/Features/ConnectionHealth`.
