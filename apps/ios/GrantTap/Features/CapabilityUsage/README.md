# Capability usage interface

This feature renders authenticated MCP, skill, and CLI observations and the
chat history they came from.

- `CapabilityIdentity.swift` owns display names, icons, and grouping keys.
- `CapabilityUsageView.swift` renders aggregate metrics for the selected period.
- `UsagePeriodSummary` keeps Overview independent of the tool/provider filters;
  kind rollups count the whole period and named totals merge with retained calls.
- `SessionUsageSnapshot` attaches native token/context facts to the exact local
  provider session while preserving its Mesh, Task and computer identity.
- `CapabilityUsageHistoryView.swift` renders per-capability observations.
- Global Usage drilldowns preserve the selected period and show aggregate counts,
  failures, duration and optional CPU/memory before their retained call history.
- Resource evidence stays optional and labels measured, attributed, estimated,
  or unknown CPU/RAM honestly; Skill correlation never claims exact ownership.
- `CapabilityChatDestination.swift` resolves a usage event back to its chat.
- `ChatHistory*.swift` render archived and active transcript history.

Usage persistence is isolated in `../SecurityAndAudit/CapabilityUsageStore.swift`.
Grouping and navigation are covered by `GrantTapTests/AppRuntimeTests.swift`.
