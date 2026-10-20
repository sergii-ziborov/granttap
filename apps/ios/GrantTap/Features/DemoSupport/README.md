# Demo support

[Engineering index](../../../../../AGENTS.md) · [Graph fixture](GraphBuildFixture.swift) · [Chat work fixture](ChatActivityRailFixture.swift)

This module contains deterministic DEBUG-only data used by screenshot and UI
tests. `AppModelDemo.swift` owns lifecycle changes; `AppModelDemoFixtures.swift`
owns the sample catalog, activities, approvals, and schedules.

The module is compiled into Debug and LocalTest only because all fixture symbols
are enclosed by `#if DEBUG`. Release builds keep only `stopDemo()`, which clears
possible developer residue after connection recovery.

`GraphBuildFixture` supplies isolated empty, pending, failed, unavailable and cached-report
request states for Graph and Health UI tests. It sets no account, transport or
approval override. Retry still calls the public analysis request and reports the
fixture's missing computer route.
The unavailable report retains its repository identity error and provenance so
Health tests can inspect the reason, refresh and preserve the last reported issue.

`CortexPacketFixture` supplies an isolated completed context packet for Health
diagnostics. Tests check selected and omitted token estimates while preserving
the explicit warning that packet preparation does not prove agent receipt.

`ChatActivityRailFixture` provides four recorded edits, two nested conversations
and saved directory/text pages under a demo session. It uses the public preview
store so offline navigation exercises durable cached data. No live account or
provider process is involved.

`MeshArchiveStreamingFixture` refreshes 48 synthetic Mesh archives during Health
scrolling tests. It never connects to a live computer or changes account policy.

`DemoWorkspaceRead` holds its sample response until the UI test completes it.
The DEBUG-only completion control lets the test measure the pending loader
before checking the empty response. Cancellation releases waiting fixture reads;
tests live in `tests/DemoWorkspaceReadTests.swift`.
