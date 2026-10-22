# Demo support

[Engineering index](../../../../../AGENTS.md) · [Graph fixture](GraphBuildFixture.swift) · [Chat work fixture](ChatActivityRailFixture.swift)

The built-in demo is available in App Store builds from Explore demo, including
the Mac license and connection screens. It requires no account, purchase, local
MCP, computer or network. `AppModelDemo.swift` owns lifecycle changes;
`AppModelDemoFixtures.swift` owns the labelled sample catalog and activities.

`DemoReviewInteractions` resolves sample approvals and chat/question replies in
memory before either durable delivery queue is touched. Unrelated session or
request identities are rejected inside demo mode. No command, provider response,
computer confirmation or purchase is simulated as a real event. Automation
remains a preview. Exit Demo restores the normal licensing and connection flow.
Queued sample messages are removed on reset/exit before a later live send can
persist them. Existing real pending messages are preserved.
Additional UI-test scenarios and automatic capture launch flags are DEBUG-only.

`SandboxSubscriptionFixture` supplies isolated Sandbox and account-grant
storefronts for UI checks. It never purchases a product or creates an account;
the production screen still loads Apple's real catalog.

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
