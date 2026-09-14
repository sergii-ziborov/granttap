# Security and audit

This feature owns local security state and privacy-preserving operational history.

- `CapabilityUsageEvent.swift` defines MCP, skill, and CLI observations.
- `CapabilityUsageStore.swift` validates, merges, bounds, and persists usage.
- `AuditStore.swift` keeps the bounded on-device application log.
- `SecurityGate.swift` owns app-lock, Face ID, and GrantTap PIN transitions.

The code deliberately stores only bounded previews and authenticated chat targets.
Behavior is covered by `GrantTapTests/AppRuntimeTests.swift`,
`SecurityLockPolicyTests.swift`, and `SecurityPinTests.swift`.
