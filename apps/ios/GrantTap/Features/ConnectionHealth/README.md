# Connection health

This feature separates honest machine freshness from the phone WebSocket state.
`ConnectionSnapshot.swift` defines the phases, `AppModelConnectionHealth.swift`
derives them from authenticated room state, and `SettingsConnectionSection.swift`
renders per-computer reconnect/prefer/unlink controls.

Connection routing and multi-computer regressions live in
`GrantTapTests/AppRuntimeTests.swift`.

`ProviderHookReviewView` shows native Codex hook trust for a selected computer.
A person reviews the full command and hash before confirming one definition.
The request targets that computer and hash; the client accepts success only
from the matching room, endpoint, and request with the same enabled, trusted
native definition. Timeout, modified definitions, and unavailable status do
not claim success. Tests live in `GrantTapTests/Features/ConnectionHealth`.
