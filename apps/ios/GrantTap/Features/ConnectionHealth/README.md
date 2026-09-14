# Connection health

This feature separates honest machine freshness from the phone WebSocket state.
`ConnectionSnapshot.swift` defines the phases, `AppModelConnectionHealth.swift`
derives them from authenticated room state, and `SettingsConnectionSection.swift`
renders per-computer reconnect/prefer/unlink controls.

Connection routing and multi-computer regressions live in
`GrantTapTests/AppRuntimeTests.swift`.
