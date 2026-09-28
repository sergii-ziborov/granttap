# Local MCP on Mac

`MacLocalMCPModel` is the Apple-client entry point for the installed GrantTap MCP.
It discovers the loopback status endpoint and uses its same-user Unix socket for
bounded Mesh, Task, conversation, image, usage, and capability operations.
The machine runtime remains in the sibling `granttap-mcp` repository.

`MacLocalMCPPolicy` validates status, acknowledgement, and rejection payloads,
preserves policy drafts, and applies revisions through the canonical runtime.
`MacLocalMCPApproval` reads the actual Mesh auto-accept value and writes only the
selected Mesh. Local observations use the `local-mac` usage source without adding
that source to relay routing.

Usage includes provider-reported token facts keyed by native session and provider.
`SessionUsageSnapshot` enriches only executions on the discovered local endpoint;
it preserves Task, Project and computer identity. Counts and period rollups live
in `CapabilityUsage`; tool-list filters do not change the overview.

The Mac shell keeps the native window controls and places the brand above the
navigation stack in normal layout, so pushing a detail cannot move the header.
Local MCP discovery belongs to startup; computer-network pairing belongs to
Settings. Tests for the shared policy and usage behavior are under
`GrantTapTests/Features/ProjectMesh`; runtime validation tests belong to the MCP.
Shared usage regressions also live in `GrantTapTests/Features/CapabilityUsage`.

Settings offers **Connect iPhone or iPad**, displaying a separate one-use QR
from the local MCP, and **Connect a computer by link**, adding another computer
through its encrypted mailbox, or importing the device-network invitation
from an iPhone as one atomic registry update. Existing connections are retained. Enrollment
completes when that new device is observed; saving a computer link does not
claim that it is online. Codes remain in memory and disappear on expiry or
completion.

`DesktopCatalogSources` combines local observations with authenticated computer
catalogs. `MacCatalogRouting` checks Project, Task, provider, native session and
computer before choosing the local socket. Refreshing one computer cannot
replace another computer's list. Tests are in
`GrantTapTests/Features/MacLocalMCP` and `GrantTapTests/Features/Pairing`.

See [`AGENTS.md`](../../../../../AGENTS.md) for the repository contract.

Generated image references are advertised by the exact Task conversation and
fetched with `desktop.task_image`. The client never reads provider transcripts
or arbitrary local paths. Native messages retain up to 16,384 UTF-16 units;
the runtime also bounds the whole response to fit the socket frame.

The existing refresh loop reads `desktop.live_catalog` every five seconds when
MCP is ready. `MacLiveSessionProjection` checks the exact Project, Task, native
session, provider, computer and current owner before applying its live state
and progress to Now. A fresh native turn can supersede an older closure in the
presentation; it does not rewrite durable Execution history or handoff rights.
Completed Tasks and former owners are excluded. Reports expire after one minute.

The existing This Mac Settings section includes Codex hook review.
`MacLocalProviderHooks.swift` carries a displayed hook approval through the
same private desktop socket and decodes its correlated native confirmation.
Status discovery and refresh never approve hooks. The review screen and model
validation are shared with iPhone/iPad under ConnectionHealth.

`MacLocalAttachmentBatch` prepares bounded private file copies for local Task
sends and creation. Only the small path/name/MIME manifest travels over the
same-user socket. The MCP validates and reads the batch and passes it through
the existing provider attachment pipeline. Copies are removed after the request
or any error. Source picker files and unrelated directories are untouched.
