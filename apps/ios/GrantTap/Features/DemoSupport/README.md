# Demo support

[public source](https://github.com/sergii-ziborov/granttap) · [Graph fixture](GraphBuildFixture.swift) · [Chat work fixture](ChatActivityRailFixture.swift)

This module contains deterministic DEBUG-only data used by screenshot and UI
tests. `AppModelDemo.swift` owns lifecycle changes; `AppModelDemoFixtures.swift`
owns the sample catalog, activities, approvals, and schedules.

The module is compiled into Debug and LocalTest only because all fixture symbols
are enclosed by `#if DEBUG`. Release builds keep only `stopDemo()`, which clears
possible developer residue after connection recovery.

`GraphBuildFixture` supplies isolated empty, pending, failed and cached-report
request states for Graph and Health UI tests. It sets no account, transport or
approval override. Retry still calls the public analysis request and reports the
fixture's missing computer route.

`ChatActivityRailFixture` provides four recorded edits, two nested conversations
and saved directory/text pages under a demo session. It uses the public preview
store so offline navigation exercises durable cached data. No live account or
provider process is involved.
