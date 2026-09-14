# Capability usage interface

This feature renders authenticated MCP, skill, and CLI observations and the
chat history they came from.

- `CapabilityIdentity.swift` owns display names, icons, and grouping keys.
- `CapabilityUsageView.swift` renders global policy and aggregate metrics.
- `CapabilityUsageHistoryView.swift` renders per-capability observations.
- Resource evidence stays optional and labels measured, attributed, estimated,
  or unknown CPU/RAM honestly; Skill correlation never claims exact ownership.
- `CapabilityChatDestination.swift` resolves a usage event back to its chat.
- `ChatHistory*.swift` render archived and active transcript history.

Usage persistence is isolated in `../SecurityAndAudit/CapabilityUsageStore.swift`.
Grouping and navigation are covered by `GrantTapTests/AppRuntimeTests.swift`.
