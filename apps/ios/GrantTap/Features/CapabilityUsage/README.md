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

The shared `ProviderAccountUsage` projection renders independently reported
subscription windows with freshness and reset times. All four provider model
IDs remain provider-scoped. Usage model rows open the sessions they counted;
missing limits are not reported as unlimited or zero use.

## Rendering and navigation

`UsageSummaries` is an immutable counted snapshot: rows, reported rollups and
resource observations are merged once. Reading it while rendering never scans
all observations again. The Usage screen builds one period/filter projection
per render and shares the concurrency map between every tool row. Provider
sessions are grouped once. Opening Usage consumes the existing live feed;
explicit pull-to-refresh still refreshes metadata. The Mac's existing shell
poll supplies automatic updates without restarting a full Mesh read on entry.
Tool labels format in their own lazy row bodies, using one relative-date formatter,
so entering the screen does not format the entire offscreen tool list.

The modern Mac navigation host is retained when switching between root pages.
Leaving a view-based drilldown explicitly resets it, since these destinations
are absent from the typed chat/Mesh path. Clicking the current Usage root keeps
its period and filters. `UsageRenderingPerformanceTests` covers the full retained
feed; `MacUsageNavigationUITests` verifies loaded navigation and drilldown exit.
